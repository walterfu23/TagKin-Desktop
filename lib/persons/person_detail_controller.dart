import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show personsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';

/// Lifecycle of a per-person detail controller (D9).
enum PersonDetailPhase { idle, loading, ready, busy, error }

/// Owns load + confirm / split / unlink / reassign / rename for one person.
///
/// Never sends `ownerUserId` (R10). Never handles likeness vectors or pixels
/// (R1). Similarity matching stays server-side (R8/§4).
class PersonDetailController extends ChangeNotifier {
  PersonDetailController({
    required this.personId,
    required this.personsRepository,
  });

  final String personId;
  final PersonsRepository personsRepository;

  PersonDetailPhase phase = PersonDetailPhase.idle;
  PersonDetail? detail;
  List<Person> otherPersons = const [];
  Object? error;

  bool get isBusy => phase == PersonDetailPhase.busy;
  bool get canConfirm =>
      detail != null &&
      detail!.linkState == LinkState.suggested &&
      !isBusy;

  /// Loads person detail + the full persons list (for reassign targets).
  Future<void> load() async {
    phase = PersonDetailPhase.loading;
    error = null;
    notifyListeners();

    try {
      final loaded = await personsRepository.getPerson(personId);
      if (_disposed) return;
      final all = await personsRepository.listPersons();
      if (_disposed) return;
      detail = loaded;
      otherPersons = all.where((p) => p.id != personId).toList();
      phase = PersonDetailPhase.ready;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      error = e;
      detail = null;
      phase = PersonDetailPhase.error;
      notifyListeners();
    }
  }

  /// Confirms this person's suggested appearance-links (R6).
  Future<void> confirm() async {
    if (!canConfirm) return;
    phase = PersonDetailPhase.busy;
    error = null;
    notifyListeners();

    try {
      final updated = await personsRepository.confirmPerson(personId);
      if (_disposed) return;
      detail = updated;
      phase = PersonDetailPhase.ready;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      error = e;
      phase = PersonDetailPhase.error;
      notifyListeners();
    }
  }

  /// Moves [appearanceIds] onto a newly created person (R6).
  ///
  /// Reloads this person afterward so the split appearances disappear here.
  Future<PersonDetail?> split(List<String> appearanceIds) async {
    if (detail == null || isBusy || appearanceIds.isEmpty) return null;
    phase = PersonDetailPhase.busy;
    error = null;
    notifyListeners();

    try {
      final created = await personsRepository.splitPerson(
        personId,
        appearanceIds,
      );
      if (_disposed) return null;
      // Refresh this person + other-persons list (new person is a reassign target).
      await load();
      return created;
    } catch (e) {
      if (_disposed) return null;
      error = e;
      phase = PersonDetailPhase.error;
      notifyListeners();
      return null;
    }
  }

  /// Clears [appearanceId]'s personId (R6 — always reversible).
  Future<void> unlink(String appearanceId) async {
    if (detail == null || isBusy) return;
    phase = PersonDetailPhase.busy;
    error = null;
    notifyListeners();

    try {
      await personsRepository.unlinkAppearance(appearanceId);
      if (_disposed) return;
      await load();
    } catch (e) {
      if (_disposed) return;
      error = e;
      phase = PersonDetailPhase.error;
      notifyListeners();
    }
  }

  /// Moves [appearanceId] onto [targetPersonId] as confirmed (R6).
  Future<void> reassign(String appearanceId, String targetPersonId) async {
    if (detail == null || isBusy) return;
    phase = PersonDetailPhase.busy;
    error = null;
    notifyListeners();

    try {
      await personsRepository.reassignAppearance(
        appearanceId,
        targetPersonId,
      );
      if (_disposed) return;
      await load();
    } catch (e) {
      if (_disposed) return;
      error = e;
      phase = PersonDetailPhase.error;
      notifyListeners();
    }
  }

  /// Renames this person (human-authored; R6). Empty → null.
  Future<void> rename(String? name) async {
    if (detail == null || isBusy) return;
    phase = PersonDetailPhase.busy;
    error = null;
    notifyListeners();

    try {
      final trimmed = name?.trim();
      final updated = await personsRepository.renamePerson(
        personId,
        (trimmed == null || trimmed.isEmpty) ? null : trimmed,
      );
      if (_disposed) return;
      detail = PersonDetail(
        id: updated.id,
        name: updated.name,
        linkState: updated.linkState,
        createdAt: updated.createdAt,
        appearances: detail!.appearances,
      );
      phase = PersonDetailPhase.ready;
      notifyListeners();
    } catch (e) {
      if (_disposed) return;
      error = e;
      phase = PersonDetailPhase.error;
      notifyListeners();
    }
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Per-person [PersonDetailController].
final personDetailControllerProvider =
    Provider.autoDispose.family<PersonDetailController, String>(
  (ref, personId) {
    final controller = PersonDetailController(
      personId: personId,
      personsRepository: ref.watch(personsRepositoryProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [personsRepositoryProvider],
);
