import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/persons/collection_dialogs.dart';
import 'package:tagkin_desktop/persons/collection_navigation.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';

/// Blocking start gate when the catalog has collections but none was resumed
/// (missing or stale [CollectionsFile.currentCollectionId]).
///
/// Under development — not shipped.
class CollectionStartGate extends ConsumerWidget {
  const CollectionStartGate({
    super.key,
    required this.libraryFolders,
    this.onSignOut,
  });

  final List<String> libraryFolders;
  final Future<void> Function()? onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = ref.watch(collectionsControllerProvider);
    final recents = cols.recentCollections;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Choose a collection',
                  key: const Key('collection-start-gate-title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Open a recent collection, browse all, or create a new one.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (recents.isNotEmpty) ...[
                  Text(
                    'Recents',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  for (final c in recents)
                    ListTile(
                      key: Key('collection-start-recent-${c.id}'),
                      title: Text(c.name),
                      leading: const Icon(Icons.history),
                      onTap: () async {
                        cols.setLibraryFolders(libraryFolders);
                        await cols.open(c.id);
                      },
                    ),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  key: const Key('collection-start-new'),
                  onPressed: () async {
                    final name = await showCollectionNameDialog(
                      context,
                      title: 'New collection',
                      confirmLabel: 'Create',
                    );
                    if (name == null) return;
                    cols.setLibraryFolders(libraryFolders);
                    final ok = await cols.create(
                      name: name,
                      seedFolders: libraryFolders,
                    );
                    if (!context.mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not create collection (empty or duplicate name).',
                          ),
                        ),
                      );
                    }
                  },
                  child: const Text('New collection…'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('collection-start-open'),
                  onPressed: () async {
                    final id = await showOpenCollectionDialog(
                      context,
                      collections: [
                        for (final c in cols.collections)
                          (id: c.id, name: c.name),
                      ],
                    );
                    if (id == null) return;
                    cols.setLibraryFolders(libraryFolders);
                    await cols.open(id);
                  },
                  child: const Text('Open collection…'),
                ),
                if (onSignOut != null) ...[
                  const SizedBox(height: 24),
                  TextButton(
                    key: const Key('collection-start-sign-out'),
                    onPressed: () => onSignOut!(),
                    child: const Text('Sign out'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared handlers for File menu / AppBar collection commands.
Future<void> runCollectionMenuCommand({
  required BuildContext context,
  required CollectionsController cols,
  required CollectionMenuCommand command,
  required List<String> libraryFolders,
  String? recentCollectionId,
}) async {
  cols.setLibraryFolders(libraryFolders);
  Future<DirtyPromptChoice> dirty() => showCollectionDirtyPrompt(context);

  switch (command) {
    case CollectionMenuCommand.newCollection:
      final name = await showCollectionNameDialog(
        context,
        title: 'New collection',
        confirmLabel: 'Create',
      );
      if (name == null || !context.mounted) return;
      final ok = await cols.create(
        name: name,
        seedFolders: libraryFolders,
        resolveDirty: dirty,
      );
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not create collection (empty/duplicate name, or cancelled).',
            ),
          ),
        );
      }
    case CollectionMenuCommand.open:
      final id = await showOpenCollectionDialog(
        context,
        collections: [
          for (final c in cols.collections) (id: c.id, name: c.name),
        ],
      );
      if (id == null || !context.mounted) return;
      await cols.open(id, resolveDirty: dirty);
    case CollectionMenuCommand.openRecent:
      final id = recentCollectionId;
      if (id == null) return;
      await cols.open(id, resolveDirty: dirty);
    case CollectionMenuCommand.save:
      if (!cols.hasCurrent) return;
      await cols.save();
    case CollectionMenuCommand.saveAs:
      if (!cols.hasCurrent) return;
      final name = await showCollectionNameDialog(
        context,
        title: 'Save collection as',
        confirmLabel: 'Save as',
      );
      if (name == null || !context.mounted) return;
      if (!await cols.saveAs(name) && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not Save as (empty or duplicate name).'),
          ),
        );
      }
    case CollectionMenuCommand.rename:
      if (!cols.hasCurrent) return;
      final name = await showCollectionNameDialog(
        context,
        initialName: cols.current.name,
        title: 'Rename collection',
        confirmLabel: 'Rename',
      );
      if (name == null || !context.mounted) return;
      if (!cols.rename(name)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not rename (empty or duplicate name).'),
          ),
        );
      }
    case CollectionMenuCommand.delete:
      if (!cols.hasCurrent) return;
      await cols.delete(
        confirm: () => showDeleteCollectionDialog(
          context,
          name: cols.current.name,
        ),
      );
    case CollectionMenuCommand.addFolder:
      if (!cols.hasCurrent) return;
      final currentFolders = cols.current.leafFolders.toSet();
      final candidates = [
        for (final f in libraryFolders)
          if (!currentFolders.contains(f)) f,
      ];
      if (candidates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All library folders are already in this collection.'),
          ),
        );
        return;
      }
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          key: const Key('collection-add-folder-dialog'),
          title: const Text('Add folder'),
          children: [
            for (final f in candidates)
              SimpleDialogOption(
                key: Key('collection-add-folder-option-$f'),
                onPressed: () => Navigator.of(ctx).pop(f),
                child: Text(leafFolderLabel(f)),
              ),
          ],
        ),
      );
      if (picked == null) return;
      cols.addFolder(picked);
    case CollectionMenuCommand.removeFolder:
      if (!cols.hasCurrent) return;
      final members = cols.current.leafFolders;
      if (members.isEmpty) return;
      final picked = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          key: const Key('collection-remove-folder-dialog'),
          title: const Text('Remove folder'),
          children: [
            for (final f in members)
              SimpleDialogOption(
                key: Key('collection-remove-folder-option-$f'),
                onPressed: () => Navigator.of(ctx).pop(f),
                child: Text(leafFolderLabel(f)),
              ),
          ],
        ),
      );
      if (picked == null) return;
      cols.removeFolder(picked);
  }
}
