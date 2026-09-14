import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/dirty_leave_prompt.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';

enum _ViewsCmd { all, saveAs, update, rename, delete, manage }

class _ViewsSel {
  const _ViewsSel.cmd(this.cmd) : viewId = null;
  const _ViewsSel.recent(this.viewId) : cmd = null;

  final _ViewsCmd? cmd;
  final String? viewId;
}

/// Apply a saved view's filters and mark it active.
Future<void> applySavedView({
  required LibraryTableController table,
  required DesktopPrefsController prefs,
  required SavedView view,
  CollectionsController? cols,
}) async {
  await table.runViewCommitPaused(() async {
    await table.applyLibraryViewFilters(view.filters);
    await prefs.setHideBlurryPhotos(view.filters.hideBlurryPhotos);
    table.setActiveView(view.id, view.filters);
    await cols?.touchViewRecent(view.id);
  });
}

/// Reset Folders filters to the built-in All view.
Future<void> applyAllView({
  required LibraryTableController table,
  required DesktopPrefsController prefs,
}) async {
  await table.runViewCommitPaused(() async {
    await table.applyLibraryViewFilters(LibraryViewFilters.all);
    await prefs.setHideBlurryPhotos(false);
    table.setActiveView(null, LibraryViewFilters.all);
  });
}

/// Persist the current Folders filters onto a View.
///
/// All stays empty: the first real mutation (not Hide-column, ingest, or
/// Remove folder) mints View01, View02, … and switches to it. Named views
/// stay dirty until Update or a leave-prompt Save. Hide-column is never
/// written by this helper.
Future<void> commitActiveView({
  required LibraryTableController table,
  required CollectionsController cols,
}) async {
  if (table.viewCommitPaused || !cols.sessionReady) return;
  if (table.activeViewId != null) return;
  if (!_viewCommitNeeded(table)) return;
  table.viewCommitPaused = true;
  try {
    await _commitActiveViewBody(table: table, cols: cols);
  } finally {
    table.viewCommitPaused = false;
  }
}

/// Write the live filters onto the active named view (Update / leave Save).
Future<void> saveNamedActiveView({
  required LibraryTableController table,
  required CollectionsController cols,
}) async {
  if (table.viewCommitPaused || !cols.sessionReady) return;
  final id = table.activeViewId;
  if (id == null) return;
  table.viewCommitPaused = true;
  try {
    final persist = table.persistableViewFilters();
    final ok = await cols.updateView(id, persist);
    if (!ok) return;
    table.setActiveView(id, persist);
  } finally {
    table.viewCommitPaused = false;
  }
}

/// Revert live filters to the last saved named-view snapshot.
Future<void> discardActiveViewChanges({
  required LibraryTableController table,
  required DesktopPrefsController prefs,
}) async {
  final snap = table.activeViewSnapshot;
  if (snap == null || table.activeViewId == null) {
    await applyAllView(table: table, prefs: prefs);
    return;
  }
  await table.runViewCommitPaused(() async {
    await table.applyLibraryViewFilters(snap);
    await prefs.setHideBlurryPhotos(snap.hideBlurryPhotos);
    table.setActiveView(table.activeViewId, snap);
  });
}

/// Save / Discard / Cancel when a named view is dirty.
Future<bool> confirmLeaveIfViewDirty({
  required BuildContext context,
  required LibraryTableController table,
  required CollectionsController cols,
  required DesktopPrefsController prefs,
  Future<DirtyPromptChoice> Function()? resolveDirty,
}) async {
  if (!table.isActiveViewModified) return true;
  final choice =
      await (resolveDirty ?? () => showViewDirtyLeaveOverlayPrompt(context))();
  if (choice == DirtyPromptChoice.cancel) return false;
  if (choice == DirtyPromptChoice.discard) {
    await discardActiveViewChanges(table: table, prefs: prefs);
    return true;
  }
  await saveNamedActiveView(table: table, cols: cols);
  return true;
}

bool _viewCommitNeeded(LibraryTableController table) {
  final persist = table.persistableViewFilters();
  if (persist == LibraryViewFilters.all) return false;
  final snap = table.activeViewSnapshot;
  if (snap != null && persist == snap) return false;
  return true;
}

Future<void> _commitActiveViewBody({
  required LibraryTableController table,
  required CollectionsController cols,
}) async {
  final persist = table.persistableViewFilters();
  final saved = await cols.saveView(
    name: cols.nextDefaultViewName(),
    filters: persist,
  );
  if (saved == null) return;
  table.setActiveView(saved.id, saved.filters);
}

/// Folders toolbar Views menu: All, recents, save / update / rename / delete.
class ViewsMenu extends ConsumerWidget {
  const ViewsMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = ref.watch(collectionsControllerProvider);
    final table = ref.watch(libraryTableControllerProvider);
    final activeId = table.activeViewId;
    final active = activeId == null ? null : cols.viewById(activeId);
    final label = active?.name ?? 'All';
    final shown = table.isActiveViewModified ? '$label*' : label;
    final recents = cols.recentViews;
    final canMutate = cols.sessionReady;

    return PopupMenuButton<_ViewsSel>(
      key: const Key('library-views-menu'),
      tooltip: 'Views',
      onSelected: (sel) {
        unawaited(_onSelected(context, ref, sel));
      },
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            key: const Key('views-menu-all'),
            value: const _ViewsSel.cmd(_ViewsCmd.all),
            child: Text(active == null ? 'All ✓' : 'All'),
          ),
          if (recents.isNotEmpty) const PopupMenuDivider(),
          for (final v in recents)
            PopupMenuItem(
              key: Key('views-menu-recent-${v.id}'),
              value: _ViewsSel.recent(v.id),
              child: Text(
                v.id == activeId ? '${v.name} ✓' : v.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            key: const Key('views-menu-save-as'),
            enabled: canMutate,
            value: const _ViewsSel.cmd(_ViewsCmd.saveAs),
            child: const Text('Save as new view…'),
          ),
          PopupMenuItem(
            key: const Key('views-menu-update'),
            enabled: canMutate && active != null && table.isActiveViewModified,
            value: const _ViewsSel.cmd(_ViewsCmd.update),
            child: Text(
              active == null ? 'Update view' : 'Update "${active.name}"',
            ),
          ),
          PopupMenuItem(
            key: const Key('views-menu-rename'),
            enabled: canMutate && active != null,
            value: const _ViewsSel.cmd(_ViewsCmd.rename),
            child: const Text('Rename / describe…'),
          ),
          PopupMenuItem(
            key: const Key('views-menu-delete'),
            enabled: canMutate && active != null,
            value: const _ViewsSel.cmd(_ViewsCmd.delete),
            child: const Text('Delete view'),
          ),
          PopupMenuItem(
            key: const Key('views-menu-manage'),
            enabled: canMutate,
            value: const _ViewsSel.cmd(_ViewsCmd.manage),
            child: const Text('Manage views…'),
          ),
        ];
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.layers_outlined, size: 18),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                shown,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _onSelected(
    BuildContext context,
    WidgetRef ref,
    _ViewsSel sel,
  ) async {
    final cols = ref.read(collectionsControllerProvider);
    final table = ref.read(libraryTableControllerProvider);
    final prefs = ref.read(desktopPrefsControllerProvider);
    final viewId = sel.viewId;
    if (viewId != null) {
      if (table.activeViewId == viewId) return;
      final view = cols.viewById(viewId);
      if (view == null) return;
      final ok = await confirmLeaveIfViewDirty(
        context: context,
        table: table,
        cols: cols,
        prefs: prefs,
      );
      if (!ok) return;
      await applySavedView(table: table, prefs: prefs, view: view, cols: cols);
      return;
    }
    switch (sel.cmd) {
      case _ViewsCmd.all:
        if (table.activeViewId == null) return;
        final ok = await confirmLeaveIfViewDirty(
          context: context,
          table: table,
          cols: cols,
          prefs: prefs,
        );
        if (!ok) return;
        await applyAllView(table: table, prefs: prefs);
      case _ViewsCmd.saveAs:
        await _saveAs(context, cols, table);
      case _ViewsCmd.update:
        await saveNamedActiveView(table: table, cols: cols);
      case _ViewsCmd.rename:
        await _rename(context, cols, table);
      case _ViewsCmd.delete:
        await _delete(context, cols, table, prefs);
      case _ViewsCmd.manage:
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _ManageViewsDialog(cols: cols, table: table, prefs: prefs),
        );
      case null:
        break;
    }
  }

  Future<void> _saveAs(
    BuildContext context,
    CollectionsController cols,
    LibraryTableController table,
  ) async {
    final result = await showViewNameDialog(
      context,
      title: 'Save as new view',
      confirmLabel: 'Save',
    );
    if (result == null) return;
    final saved = await cols.saveView(
      name: result.name,
      description: result.description,
      filters: table.persistableViewFilters(),
    );
    if (saved == null) return;
    table.setActiveView(saved.id, saved.filters);
  }

  Future<void> _rename(
    BuildContext context,
    CollectionsController cols,
    LibraryTableController table,
  ) async {
    final id = table.activeViewId;
    if (id == null) return;
    final current = cols.viewById(id);
    if (current == null) return;
    final result = await showViewNameDialog(
      context,
      title: 'Rename view',
      confirmLabel: 'Save',
      initialName: current.name,
      initialDescription: current.description,
    );
    if (result == null) return;
    await cols.renameView(
      id,
      name: result.name,
      description: result.description,
    );
  }

  Future<void> _delete(
    BuildContext context,
    CollectionsController cols,
    LibraryTableController table,
    DesktopPrefsController prefs,
  ) async {
    final id = table.activeViewId;
    if (id == null) return;
    final current = cols.viewById(id);
    if (current == null) return;
    final ok = await _confirmDeleteView(context, current.name);
    if (!ok) return;
    await cols.deleteView(id);
    if (table.activeViewId == id) {
      await applyAllView(table: table, prefs: prefs);
    }
  }
}

Future<bool> _confirmDeleteView(BuildContext context, String name) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('view-delete-dialog'),
      title: const Text('Delete view?'),
      content: Text('Delete "$name"? This cannot be undone.'),
      actions: [
        TextButton(
          key: const Key('view-delete-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('view-delete-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Name + description dialog for Save as / Rename.
Future<({String name, String description})?> showViewNameDialog(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
  String initialDescription = '',
}) {
  return showDialog<({String name, String description})>(
    context: context,
    builder: (ctx) => _ViewNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialDescription: initialDescription,
    ),
  );
}

class _ViewNameDialog extends StatefulWidget {
  const _ViewNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialDescription,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final String initialDescription;

  @override
  State<_ViewNameDialog> createState() => _ViewNameDialogState();
}

class _ViewNameDialogState extends State<_ViewNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.initialDescription,
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(
      context,
    ).pop((name: trimmed, description: _description.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('view-name-dialog'),
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('view-name-field'),
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'View name',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('view-description-field'),
              controller: _description,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('view-name-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('view-name-confirm'),
          onPressed: _save,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _ManageViewsDialog extends StatelessWidget {
  const _ManageViewsDialog({
    required this.cols,
    required this.table,
    required this.prefs,
  });

  final CollectionsController cols;
  final LibraryTableController table;
  final DesktopPrefsController prefs;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cols,
      builder: (context, _) {
        final all = cols.views;
        return AlertDialog(
          key: const Key('views-manage-dialog'),
          title: const Text('Manage views'),
          content: SizedBox(
            width: 420,
            child: all.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No saved views in this collection yet.'),
                  )
                : ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final v in all)
                          ListTile(
                            key: Key('views-manage-row-${v.id}'),
                            title: Text(v.name),
                            subtitle: v.description.isEmpty
                                ? null
                                : Text(v.description),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                TextButton(
                                  key: Key('views-manage-load-${v.id}'),
                                  onPressed: () async {
                                    if (table.activeViewId != v.id) {
                                      final ok = await confirmLeaveIfViewDirty(
                                        context: context,
                                        table: table,
                                        cols: cols,
                                        prefs: prefs,
                                      );
                                      if (!ok) return;
                                    }
                                    await applySavedView(
                                      table: table,
                                      prefs: prefs,
                                      view: v,
                                      cols: cols,
                                    );
                                    if (context.mounted) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                                  child: const Text('Load'),
                                ),
                                IconButton(
                                  key: Key('views-manage-rename-${v.id}'),
                                  tooltip: 'Rename',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 18,
                                  ),
                                  onPressed: () async {
                                    final result = await showViewNameDialog(
                                      context,
                                      title: 'Rename view',
                                      confirmLabel: 'Save',
                                      initialName: v.name,
                                      initialDescription: v.description,
                                    );
                                    if (result == null) return;
                                    await cols.renameView(
                                      v.id,
                                      name: result.name,
                                      description: result.description,
                                    );
                                  },
                                ),
                                IconButton(
                                  key: Key('views-manage-delete-${v.id}'),
                                  tooltip: 'Delete',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  onPressed: () async {
                                    final ok = await _confirmDeleteView(
                                      context,
                                      v.name,
                                    );
                                    if (!ok) return;
                                    await cols.deleteView(v.id);
                                    if (table.activeViewId == v.id) {
                                      await applyAllView(
                                        table: table,
                                        prefs: prefs,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              key: const Key('views-manage-close'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
