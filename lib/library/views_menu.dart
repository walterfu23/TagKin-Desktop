import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/item_lists/item_list_navigation.dart';
import 'package:tagkin_desktop/library/folders_undo_recorder.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/dirty_leave_prompt.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';

/// Tallest the view selector panel grows before it scrolls.
const double _selectorMaxHeight = 360;

/// Compact row height for the view selector (mouse UI, not touch).
const double _selectorRowHeight = 32;

/// The selector shows a search box above this many saved views.
const int _searchThreshold = 12;

enum _ViewsCmd { saveAs, update, rename, delete, export }

class _ViewsSel {
  const _ViewsSel.cmd(this.cmd) : viewId = null, isAll = false;
  const _ViewsSel.view(this.viewId) : cmd = null, isAll = false;
  const _ViewsSel.all() : cmd = null, viewId = null, isAll = true;

  final _ViewsCmd? cmd;
  final String? viewId;
  final bool isAll;
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
    table.setActiveView(view.id, view.filters);
    await cols?.setCurrentViewId(view.id);
  });
}

/// Reset Folders filters to the built-in All view.
Future<void> applyAllView({
  required LibraryTableController table,
  required DesktopPrefsController prefs,
  CollectionsController? cols,
}) async {
  await table.runViewCommitPaused(() async {
    await table.applyLibraryViewFilters(LibraryViewFilters.all);
    table.setActiveView(null, LibraryViewFilters.all);
    await cols?.setCurrentViewId(null);
  });
}

/// Restore the collection's last Folders view (All when missing or stale).
Future<void> applyCurrentCollectionView({
  required LibraryTableController table,
  required DesktopPrefsController prefs,
  required CollectionsController cols,
}) async {
  final id = cols.current.currentViewId;
  final view = id == null ? null : cols.viewById(id);
  if (view != null) {
    await applySavedView(table: table, prefs: prefs, view: view, cols: cols);
    return;
  }
  await applyAllView(table: table, prefs: prefs, cols: cols);
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

/// Folders toolbar view selector (switch view) plus a View actions menu
/// (save / update / rename / delete / export the current view).
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
    final canMutate = cols.sessionReady;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        MenuAnchor(
          key: const Key('library-views-menu'),
          menuChildren: [
            _ViewSelectorPanel(
              views: cols.views,
              activeId: activeId,
              onPick: (sel) => unawaited(_onSelected(context, ref, sel)),
            ),
          ],
          builder: (context, controller, _) => Tooltip(
            message: 'Switch view',
            child: InkWell(
              onTap: () =>
                  controller.isOpen ? controller.close() : controller.open(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            ),
          ),
        ),
        PopupMenuButton<_ViewsSel>(
          key: const Key('library-view-actions'),
          tooltip: 'View actions',
          icon: const Icon(Icons.more_vert, size: 20),
          onSelected: (sel) {
            unawaited(_onSelected(context, ref, sel));
          },
          itemBuilder: (context) {
            return [
              PopupMenuItem(
                key: const Key('views-menu-save-as'),
                enabled: canMutate,
                value: const _ViewsSel.cmd(_ViewsCmd.saveAs),
                child: const Text('Save as new view…'),
              ),
              PopupMenuItem(
                key: const Key('views-menu-update'),
                enabled:
                    canMutate && active != null && table.isActiveViewModified,
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
              const PopupMenuDivider(),
              const PopupMenuItem(
                key: Key('views-menu-export'),
                value: _ViewsSel.cmd(_ViewsCmd.export),
                child: Text('Export this view…'),
              ),
            ];
          },
        ),
      ],
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
    if (sel.cmd == _ViewsCmd.export) {
      // Opens Export Views on the current Folders view; changes nothing here.
      requestOpenItemListExport(ref);
      return;
    }
    final label = switch (sel.cmd) {
      _ViewsCmd.saveAs => 'Save view',
      _ViewsCmd.update => 'Update view',
      _ViewsCmd.rename => 'Rename view',
      _ViewsCmd.delete => 'Delete view',
      _ViewsCmd.export || null => sel.isAll ? 'Show all' : 'Change view',
    };
    await ref
        .read(foldersUndoProvider)
        .record(
          table: table,
          cols: cols,
          label: label,
          mutate: () => _runViewCommand(context, sel, cols, table, prefs),
        );
  }

  Future<void> _runViewCommand(
    BuildContext context,
    _ViewsSel sel,
    CollectionsController cols,
    LibraryTableController table,
    DesktopPrefsController prefs,
  ) async {
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
    if (sel.isAll) {
      if (table.activeViewId == null) return;
      final ok = await confirmLeaveIfViewDirty(
        context: context,
        table: table,
        cols: cols,
        prefs: prefs,
      );
      if (!ok) return;
      await applyAllView(table: table, prefs: prefs, cols: cols);
      return;
    }
    final activeId = table.activeViewId;
    final active = activeId == null ? null : cols.viewById(activeId);
    switch (sel.cmd) {
      case _ViewsCmd.saveAs:
        await _saveAs(context, cols, table);
      case _ViewsCmd.update:
        await saveNamedActiveView(table: table, cols: cols);
      case _ViewsCmd.rename:
        if (active != null) await _rename(context, cols, active);
      case _ViewsCmd.delete:
        if (active != null) await _delete(context, cols, table, prefs, active);
      case _ViewsCmd.export || null:
        break;
    }
  }

  Future<void> _rename(
    BuildContext context,
    CollectionsController cols,
    SavedView v,
  ) async {
    final result = await showViewNameDialog(
      context,
      title: 'Rename view',
      confirmLabel: 'Save',
      initialName: v.name,
      initialDescription: v.description,
      nameTaken: (name) => cols.viewNameTaken(name, excludingId: v.id),
    );
    if (result == null) return;
    await cols.renameView(
      v.id,
      name: result.name,
      description: result.description,
    );
  }

  Future<void> _delete(
    BuildContext context,
    CollectionsController cols,
    LibraryTableController table,
    DesktopPrefsController prefs,
    SavedView v,
  ) async {
    final ok = await _confirmDeleteView(context, v.name);
    if (!ok) return;
    await cols.deleteView(v.id);
    if (table.activeViewId == v.id) {
      await applyAllView(table: table, prefs: prefs, cols: cols);
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
      nameTaken: cols.viewNameTaken,
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
  bool Function(String name)? nameTaken,
}) {
  return showDialog<({String name, String description})>(
    context: context,
    builder: (ctx) => _ViewNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      initialDescription: initialDescription,
      nameTaken: nameTaken,
    ),
  );
}

class _ViewNameDialog extends StatefulWidget {
  const _ViewNameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.initialDescription,
    this.nameTaken,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final String initialDescription;
  final bool Function(String name)? nameTaken;

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
  String? _nameError;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _name.text.trim();
    if (trimmed.isEmpty) return;
    if (widget.nameTaken?.call(trimmed) == true) {
      setState(() => _nameError = 'A view with this name already exists.');
      return;
    }
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
              decoration: InputDecoration(
                labelText: 'View name',
                border: const OutlineInputBorder(),
                errorText: _nameError,
              ),
              onChanged: (_) {
                if (_nameError == null) return;
                setState(() => _nameError = null);
              },
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

/// Body of the view selector: optional search box plus a bounded, scrolling
/// list of compact rows. Built fresh on each open, so the search starts empty.
class _ViewSelectorPanel extends StatefulWidget {
  const _ViewSelectorPanel({
    required this.views,
    required this.activeId,
    required this.onPick,
  });

  final List<SavedView> views;
  final String? activeId;
  final void Function(_ViewsSel sel) onPick;

  @override
  State<_ViewSelectorPanel> createState() => _ViewSelectorPanelState();
}

class _ViewSelectorPanelState extends State<_ViewSelectorPanel> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim().toLowerCase();

  bool get _showAll => _query.isEmpty || 'all'.contains(_query);

  List<SavedView> get _matches => [
    for (final v in widget.views)
      if (_query.isEmpty || v.name.toLowerCase().contains(_query)) v,
  ];

  void _pickFirst() {
    final first = _matches.isNotEmpty
        ? _ViewsSel.view(_matches.first.id)
        : (_showAll ? const _ViewsSel.all() : null);
    if (first == null) return;
    MenuController.maybeOf(context)?.close();
    widget.onPick(first);
  }

  Widget _row({
    required Key key,
    required String checkId,
    required bool current,
    required String label,
    required _ViewsSel sel,
  }) {
    return MenuItemButton(
      key: key,
      style: const ButtonStyle(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: WidgetStatePropertyAll(Size(0, _selectorRowHeight)),
        maximumSize: WidgetStatePropertyAll(
          Size(double.infinity, _selectorRowHeight),
        ),
        padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12)),
      ),
      onPressed: () => widget.onPick(sel),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: current
                ? Icon(
                    Icons.check,
                    size: 18,
                    key: Key('views-menu-check-$checkId'),
                  )
                : null,
          ),
          Expanded(child: Text(label, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.views.length > _searchThreshold)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: TextField(
                key: const Key('views-menu-search'),
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Find a view',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _pickFirst(),
              ),
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: _selectorMaxHeight),
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_showAll)
                      _row(
                        key: const Key('views-menu-all'),
                        checkId: 'all',
                        current: widget.activeId == null,
                        label: 'All',
                        sel: const _ViewsSel.all(),
                      ),
                    for (final v in matches)
                      _row(
                        key: Key('views-menu-view-${v.id}'),
                        checkId: v.id,
                        current: v.id == widget.activeId,
                        label: v.name,
                        sel: _ViewsSel.view(v.id),
                      ),
                    if (matches.isEmpty && !_showAll)
                      const Padding(
                        key: Key('views-menu-no-match'),
                        padding: EdgeInsets.all(12),
                        child: Text('No matching views'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
