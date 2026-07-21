import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show jobsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/jobs/job_state_view.dart';

/// Lifecycle phase of a per-item jobs controller (D7).
enum JobsPhase { idle, analyzing, polling, terminal, error }

/// Owns analyze trigger, job-progress polling, cancel, retry, and delete for
/// one item. Never estimates cost or routes providers (R8/R9). Never sends
/// `ownerUserId` (R10). Never touches local media on delete (R1/R5).
class JobsController extends ChangeNotifier {
  JobsController({
    required this.itemId,
    required this.jobsRepository,
    this.pollInterval = const Duration(seconds: 2),
    this.ticker,
  });

  final String itemId;
  final JobsRepository jobsRepository;

  /// Interval between `GET /jobs` polls while non-terminal.
  final Duration pollInterval;

  /// Injectable timer factory for tests (`(d, cb) => Timer(d, cb)`).
  final Timer Function(Duration duration, void Function() callback)? ticker;

  JobsPhase phase = JobsPhase.idle;
  Job? latestJob;
  Item? item;
  Object? error;
  bool deleted = false;

  Timer? _pollTimer;
  bool _disposed = false;

  bool get isBusy =>
      phase == JobsPhase.analyzing || phase == JobsPhase.polling;

  bool get canRetry =>
      latestJob?.state == JobState.failed && !isBusy && !deleted;

  bool get canCancel => isBusy && !deleted;

  /// Loads the latest job once; starts polling when non-terminal.
  Future<void> refreshJobs() async {
    if (deleted) return;
    try {
      final jobs = await jobsRepository.listItemJobs(itemId);
      if (_disposed || deleted) return;
      // Cancel/delete may have finished while this list was in flight — do not
      // clobber the terminal job (e.g. cancelled) with a stale snapshot.
      if (phase == JobsPhase.terminal) return;
      latestJob = jobs.isEmpty ? null : jobs.first;
      error = null;
      if (latestJob != null && !isTerminalJobState(latestJob!.state)) {
        phase = JobsPhase.polling;
        _ensurePolling();
      } else if (latestJob != null) {
        phase = JobsPhase.terminal;
        _stopPolling();
      } else {
        phase = JobsPhase.idle;
        _stopPolling();
      }
      notifyListeners();
    } catch (e) {
      if (_disposed || deleted || phase == JobsPhase.terminal) return;
      error = e;
      phase = JobsPhase.error;
      _stopPolling();
      notifyListeners();
    }
  }

  /// Triggers analysis for a **photo** item only (R9 — never video).
  ///
  /// On success, adopts the returned [Item] and starts job polling. A server
  /// `409` BudgetExceeded surfaces via [error] with no auto-retry.
  Future<void> analyze({required ItemType itemType}) async {
    if (deleted || isBusy) return;
    if (itemType != ItemType.photo) {
      error = StateError(
        'Analyze is photo-only (R9); video items cannot trigger tagging',
      );
      phase = JobsPhase.error;
      notifyListeners();
      return;
    }

    phase = JobsPhase.analyzing;
    error = null;
    notifyListeners();

    try {
      final result = await jobsRepository.analyzeItem(itemId);
      if (_disposed || deleted) return;
      // User may have cancelled while the analyze HTTP call was in flight.
      if (phase != JobsPhase.analyzing) return;
      item = result.item;
      // After a sync analyze, poll once (and keep polling if somehow still open).
      await _pollOnce();
    } catch (e) {
      if (_disposed || deleted) return;
      if (phase != JobsPhase.analyzing) return;
      error = e;
      phase = JobsPhase.error;
      _stopPolling();
      notifyListeners();
    }
  }

  /// Re-triggers analyze after a failed job (server owns idempotency).
  Future<void> retry({required ItemType itemType}) async {
    if (!canRetry) return;
    await analyze(itemType: itemType);
  }

  /// Cancels unfinished work, stops polling, and adopts the cancel response.
  Future<void> cancel() async {
    if (deleted) return;
    _stopPolling();
    try {
      final result = await jobsRepository.cancelItem(itemId);
      if (_disposed) return;
      item = result.item;
      latestJob = result.job;
      error = null;
      if (latestJob != null && isTerminalJobState(latestJob!.state)) {
        phase = JobsPhase.terminal;
      } else if (latestJob != null) {
        // Unexpected non-terminal after cancel — treat as terminal cancelled UI.
        phase = JobsPhase.terminal;
      } else {
        phase = JobsPhase.terminal;
      }
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      error = e;
      phase = JobsPhase.error;
      notifyListeners();
    }
  }

  /// Soft-deletes the item via the API. Never touches local media paths.
  Future<void> delete() async {
    if (deleted) return;
    _stopPolling();
    try {
      await jobsRepository.deleteItem(itemId);
      if (_disposed) return;
      deleted = true;
      error = null;
      phase = JobsPhase.terminal;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      error = e;
      phase = JobsPhase.error;
      notifyListeners();
    }
  }

  Future<void> _pollOnce() async {
    final jobs = await jobsRepository.listItemJobs(itemId);
    if (_disposed) return;
    latestJob = jobs.isEmpty ? null : jobs.first;
    if (latestJob != null && !isTerminalJobState(latestJob!.state)) {
      phase = JobsPhase.polling;
      _ensurePolling();
    } else {
      phase = JobsPhase.terminal;
      _stopPolling();
    }
    notifyListeners();
  }

  void _ensurePolling() {
    if (_pollTimer != null) return;
    final schedule = ticker ?? (Duration d, void Function() cb) => Timer(d, cb);
    void tick() async {
      if (_disposed || deleted || phase != JobsPhase.polling) {
        _stopPolling();
        return;
      }
      try {
        final jobs = await jobsRepository.listItemJobs(itemId);
        if (_disposed || deleted || phase != JobsPhase.polling) {
          _stopPolling();
          return;
        }
        latestJob = jobs.isEmpty ? null : jobs.first;
        error = null;
        if (latestJob == null || isTerminalJobState(latestJob!.state)) {
          phase = JobsPhase.terminal;
          _stopPolling();
        } else {
          phase = JobsPhase.polling;
          // Schedule next tick (one-shot chain so overlapping awaits don't pile up).
          _pollTimer = schedule(pollInterval, tick);
        }
        notifyListeners();
      } catch (e) {
        if (_disposed || deleted || phase != JobsPhase.polling) {
          _stopPolling();
          return;
        }
        error = e;
        phase = JobsPhase.error;
        _stopPolling();
        notifyListeners();
      }
    }

    _pollTimer = schedule(pollInterval, tick);
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}

/// Per-item [JobsController]. Dispose cancels the poll timer.
final jobsControllerProvider =
    Provider.autoDispose.family<JobsController, String>(
  (ref, itemId) {
    final controller = JobsController(
      itemId: itemId,
      jobsRepository: ref.watch(jobsRepositoryProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [jobsRepositoryProvider],
);
