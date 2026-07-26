import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show personsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';

/// Lifecycle of a per-person detail controller (D9).
enum PersonDetailPhase { idle, loading, ready, busy, error }

/// Owns load + confirm (Save) / unassign / reassign / rename for one person.
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

  /// Saves this person (suggested → confirmed) (R6).
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

  /// Clears [appearanceId]'s personId — unassign (R6 — always reversible).
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

  /// Moves [appearanceId] onto [targetPersonId], or creates a new person when
  /// [targetPersonId] is null (R6).
  Future<void> reassign(String appearanceId, String? targetPersonId) async {
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

  bool get canDelete =>
      detail != null &&
      detail!.linkState == LinkState.suggested &&
      !isBusy;

  /// Deletes this suggested person and its appearances. Returns true on success.
  Future<bool> delete() async {
    if (!canDelete) return false;
    phase = PersonDetailPhase.busy;
    error = null;
    notifyListeners();

    try {
      await personsRepository.deletePerson(personId);
      if (_disposed) return false;
      // Keep [detail] until the page pops so the last frame does not null-check.
      phase = PersonDetailPhase.ready;
      notifyListeners();
      return true;
    } catch (e) {
      if (_disposed) return false;
      error = e;
      phase = PersonDetailPhase.error;
      notifyListeners();
      return false;
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
