import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show itemsRepositoryProvider, personsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/folders_undo_recorder.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';

/// Faces touched by one Who edit, including alike faces on other items.
class WhoEditResult {
  const WhoEditResult({
    required this.affectedItemIds,
    this.alsoMoved = const [],
    this.destName,
  });

  final Set<String> affectedItemIds;
  final List<PersonAppearance> alsoMoved;
  final String? destName;

  String? get snackbar {
    if (alsoMoved.isEmpty) return null;
    final n = alsoMoved.length;
    final faces = n == 1 ? '1 other alike face' : '$n other alike faces';
    final dest = destName?.trim();
    if (dest != null && dest.isNotEmpty) {
      return 'Moved $faces to $dest as unconfirmed.';
    }
    return 'Moved $faces as unconfirmed.';
  }
}

/// Immediate Who edits from a Folders cell, with undo on the Folders stack.
class FolderWhoEditor {
  FolderWhoEditor({
    required this.items,
    required this.persons,
    required this.undo,
    required this.refresh,
  });

  final ItemsRepository items;
  final PersonsRepository persons;
  final UndoController undo;
  final Future<void> Function(Set<String> itemIds) refresh;

  Future<WhoEditResult> assign({
    required String itemId,
    String? tagId,
    String? personId,
    String? name,
    PersonAppearance? existing,
    String? destName,
  }) async {
    final result = await items.assignPersonToItem(
      itemId,
      personId: personId,
      name: name,
      tagId: tagId,
    );
    final affected = _affected(itemId, result.alsoMoved);
    final named = destName ?? name;
    var appearanceId = result.appearance.id;
    var movedIds = [for (final a in result.alsoMoved) a.id];
    final priorPersonId = existing?.personId;
    undo.push(
      CallbackUndoableAction(
        label: 'Assign person',
        onUndo: () async {
          if (priorPersonId != null && priorPersonId.isNotEmpty) {
            await persons.reassignAppearance(
              appearanceId,
              personId: priorPersonId,
              propagateAlike: false,
            );
          } else {
            await persons.unlinkAppearance(appearanceId);
          }
          if (movedIds.isNotEmpty) {
            await persons.declineAutoAssignAppearances(movedIds);
          }
          await refresh(affected);
        },
        onRedo: () async {
          final again = await items.assignPersonToItem(
            itemId,
            personId: personId,
            name: name,
            tagId: tagId,
          );
          appearanceId = again.appearance.id;
          movedIds = [for (final a in again.alsoMoved) a.id];
          await refresh({...affected, ..._affected(itemId, again.alsoMoved)});
        },
      ),
    );
    await refresh(affected);
    return WhoEditResult(
      affectedItemIds: affected,
      alsoMoved: result.alsoMoved,
      destName: named,
    );
  }

  Future<WhoEditResult> unassign({
    required String itemId,
    required PersonAppearance appearance,
    String? tagId,
    String? personName,
  }) async {
    final personId = appearance.personId;
    await persons.unlinkAppearance(appearance.id);
    final affected = {itemId};
    undo.push(
      CallbackUndoableAction(
        label: 'Unassign person',
        onUndo: () async {
          if (personId == null || personId.isEmpty) return;
          await items.assignPersonToItem(
            itemId,
            personId: personId,
            tagId: tagId ?? appearance.tagId,
            propagateAlike: false,
          );
          await refresh(affected);
        },
        onRedo: () async {
          await persons.unlinkAppearance(appearance.id);
          await refresh(affected);
        },
      ),
    );
    await refresh(affected);
    return WhoEditResult(affectedItemIds: affected, destName: personName);
  }

  Future<WhoEditResult> excludeFace({
    required String itemId,
    required String tagId,
  }) async {
    final created = await items.createWhoExclusion(itemId, tagId);
    var exclusionId = created.exclusion.id;
    final affected = {itemId};
    undo.push(
      CallbackUndoableAction(
        label: 'Exclude face',
        onUndo: () async {
          await items.undoWhoExclusion(itemId, exclusionId);
          await refresh(affected);
        },
        onRedo: () async {
          final again = await items.createWhoExclusion(itemId, tagId);
          exclusionId = again.exclusion.id;
          await refresh(affected);
        },
      ),
    );
    await refresh(affected);
    return WhoEditResult(affectedItemIds: affected);
  }

  Set<String> _affected(String itemId, List<PersonAppearance> moved) {
    return {
      itemId,
      for (final appearance in moved)
        if (appearance.itemId != null && appearance.itemId!.isNotEmpty)
          appearance.itemId!,
    };
  }
}

final folderWhoEditorProvider = Provider<FolderWhoEditor>((ref) {
  return FolderWhoEditor(
    items: ref.watch(itemsRepositoryProvider),
    persons: ref.watch(personsRepositoryProvider),
    undo: ref.watch(foldersUndoProvider).stack,
    refresh: (ids) {
      return ref.read(libraryTableControllerProvider).refreshRowCellsQuiet(ids);
    },
  );
}, dependencies: [
  itemsRepositoryProvider,
  personsRepositoryProvider,
  foldersUndoProvider,
  libraryTableControllerProvider,
]);
