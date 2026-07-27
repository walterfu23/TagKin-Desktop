import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/persons/face_crop_drag.dart';
import 'package:tagkin_desktop/persons/link_state_view.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';
import 'package:tagkin_desktop/persons/who_exclusion_crop_thumb.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Side-by-side face-crop trays: Assigned | Unassigned | Excluded.
///
/// Drag between columns to change crop state. Selecting a person shows rename /
/// Save / Delete chrome in the Assigned column (same controller as person detail).
class FaceCropTraysPage extends ConsumerStatefulWidget {
  const FaceCropTraysPage({super.key, this.initialPersonId});

  /// When set, load this person into the Assigned column.
  final String? initialPersonId;

  @override
  ConsumerState<FaceCropTraysPage> createState() => _FaceCropTraysPageState();
}

class _FaceCropTraysPageState extends ConsumerState<FaceCropTraysPage> {
  String? _personId;
  PersonDetailController? _assignedController;
  List<Person> _persons = const [];
  List<PersonAppearance> _unassigned = const [];
  List<WhoExclusion> _excluded = const [];
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  final _renameController = TextEditingController();
  bool _renaming = false;

  @override
  void initState() {
    super.initState();
    _personId = widget.initialPersonId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reload();
    });
  }

  @override
  void dispose() {
    _assignedController?.dispose();
    _renameController.dispose();
    super.dispose();
  }

  PersonDetailController _controllerFor(String personId) {
    final existing = _assignedController;
    if (existing != null && existing.personId == personId) return existing;
    existing?.dispose();
    final next = PersonDetailController(
      personId: personId,
      personsRepository: ref.read(personsRepositoryProvider),
    );
    _assignedController = next;
    return next;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final personsRepo = ref.read(personsRepositoryProvider);
      final persons = await personsRepo.listPersons();
      final unPage = await personsRepo.listUnassignedAppearances();
      final exPage = await personsRepo.listAccountWhoExclusions();

      // Exclude / unlink can prune the selected person server-side; clear the
      // dropdown value before rebuild or DropdownButton asserts.
      var pid = _personId;
      final stillListed =
          pid != null && persons.any((p) => p.id == pid);
      if (pid != null && !stillListed) {
        _assignedController?.dispose();
        _assignedController = null;
        pid = null;
      } else if (pid != null) {
        await _controllerFor(pid).load();
      }

      if (!mounted) return;
      setState(() {
        _personId = pid;
        _renaming = pid == null ? false : _renaming;
        _persons = persons;
        _unassigned = unPage.appearances;
        _excluded = exPage.exclusions;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _selectPerson(String? id) async {
    if (id == null) {
      setState(() {
        _personId = null;
        _renaming = false;
        _assignedController?.dispose();
        _assignedController = null;
      });
      return;
    }
    final controller = _controllerFor(id);
    setState(() {
      _personId = id;
      _renaming = false;
    });
    await controller.load();
    if (mounted) setState(() {});
  }

  Future<void> _openItem(String itemId) async {
    final container = ProviderScope.containerOf(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SelectableScope(
          child: UncontrolledProviderScope(
            container: container,
            child: ItemDetailPage(itemId: itemId),
          ),
        ),
      ),
    );
  }

  Future<void> _onDrop(FaceCropTray target, FaceCropDragData data) async {
    if (_busy || data.source == target) return;
    setState(() => _busy = true);
    try {
      final persons = ref.read(personsRepositoryProvider);
      final items = ref.read(itemsRepositoryProvider);

      switch (target) {
        case FaceCropTray.unassigned:
          if (data.isAppearance && data.appearanceId != null) {
            await persons.unlinkAppearance(data.appearanceId!);
          } else if (data.isExclusion && data.exclusionId != null) {
            await items.undoWhoExclusion(data.itemId, data.exclusionId!);
          }
        case FaceCropTray.excluded:
          final tagId = data.tagId;
          if (tagId == null) {
            throw StateError('Exclude requires a who tag id');
          }
          await items.createWhoExclusion(data.itemId, tagId);
        case FaceCropTray.assigned:
          final pid = _personId;
          if (pid == null) {
            throw StateError('Select a person before assigning');
          }
          if (data.isExclusion && data.exclusionId != null) {
            await items.undoWhoExclusion(data.itemId, data.exclusionId!);
            final tagId = data.tagId ?? data.createdFromTagId;
            final page = await persons.listUnassignedAppearances();
            PersonAppearance? match;
            for (final a in page.appearances) {
              if (a.tagId == tagId) {
                match = a;
                break;
              }
            }
            if (match == null) {
              throw StateError('Could not find appearance after undo exclude');
            }
            await persons.reassignAppearance(match.id, pid);
          } else if (data.appearanceId != null) {
            await persons.reassignAppearance(data.appearanceId!, pid);
          }
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('face-crop-trays-error'),
          content: Text('Move failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmDelete(PersonDetailController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete person?'),
        content: const Text(
          'Removes this suggested person and its face assignments. '
          'You can re-analyze photos later to recreate matches.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('face-crop-person-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await controller.delete();
    if (ok && mounted) {
      await _selectPerson(null);
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Local [_assignedController] — do not watch autoDispose
    // personDetailControllerProvider here (UncontrolledProviderScope + dispose
    // mid-build asserts "Only one task can be scheduled at a time").
    final controller = _assignedController;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face crops'),
        actions: [
          IconButton(
            key: const Key('face-crop-trays-refresh'),
            tooltip: 'Refresh',
            onPressed: _busy || _loading ? null : _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                key: Key('face-crop-trays-loading'),
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Could not load trays: $_error',
                          key: const Key('face-crop-trays-error-text'),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _reload,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildAssignedColumn(controller)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TrayColumn(
                          key: const Key('face-crop-tray-unassigned'),
                          title: 'Unassigned',
                          subtitle: '${_unassigned.length} crops',
                          onAccept: (d) => _onDrop(FaceCropTray.unassigned, d),
                          child: _AppearanceGrid(
                            appearances: _unassigned,
                            source: FaceCropTray.unassigned,
                            busy: _busy,
                            onOpenItem: _openItem,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _TrayColumn(
                          key: const Key('face-crop-tray-excluded'),
                          title: 'Excluded',
                          subtitle: '${_excluded.length} crops',
                          onAccept: (d) => _onDrop(FaceCropTray.excluded, d),
                          child: _ExclusionGrid(
                            exclusions: _excluded,
                            busy: _busy,
                            onOpenItem: _openItem,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildAssignedColumn(PersonDetailController? controller) {
    final pid = _personId;
    final selectedId =
        pid != null && _persons.any((p) => p.id == pid) ? pid : null;
    final personSelect = DropdownButtonFormField<String>(
      key: const Key('face-crop-person-select'),
      // ignore: deprecated_member_use
      value: selectedId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Person',
        border: OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final p in _persons)
          DropdownMenuItem(
            value: p.id,
            child: Text(p.name ?? p.id),
          ),
      ],
      onChanged: _busy
          ? null
          : (id) async {
              await _selectPerson(id);
            },
    );

    if (selectedId == null || controller == null) {
      return _TrayColumn(
        key: const Key('face-crop-tray-assigned'),
        title: 'Assigned',
        subtitle: 'Select a person',
        header: personSelect,
        onAccept: (d) => _onDrop(FaceCropTray.assigned, d),
        child: const Center(
          child: Text(
            'Choose a person to see assigned crops',
            key: Key('face-crop-assigned-empty'),
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final detail = controller.detail;
        final subtitle = detail?.name ??
            (controller.phase == PersonDetailPhase.loading
                ? 'Loading…'
                : selectedId);
        return _TrayColumn(
          key: const Key('face-crop-tray-assigned'),
          title: 'Assigned',
          subtitle: subtitle,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              personSelect,
              if (detail != null) ...[
                const SizedBox(height: 8),
                _PersonChrome(
                  detail: detail,
                  controller: controller,
                  renameController: _renameController,
                  renaming: _renaming,
                  busy: _busy || controller.isBusy,
                  onStartRename: () {
                    setState(() {
                      _renaming = true;
                      _renameController.text = detail.name ?? '';
                    });
                  },
                  onDoneRename: () async {
                    await controller.rename(_renameController.text);
                    if (mounted) {
                      setState(() => _renaming = false);
                      final persons =
                          await ref.read(personsRepositoryProvider).listPersons();
                      if (mounted) setState(() => _persons = persons);
                    }
                  },
                  onCancelRename: () => setState(() => _renaming = false),
                  onSave: () => controller.confirm(),
                  onDelete: () => _confirmDelete(controller),
                ),
              ],
            ],
          ),
          onAccept: (d) => _onDrop(FaceCropTray.assigned, d),
          child: detail == null
              ? Center(
                  child: controller.phase == PersonDetailPhase.loading
                      ? const CircularProgressIndicator()
                      : Text(
                          controller.error != null
                              ? 'Could not load person'
                              : 'Choose a person to see assigned crops',
                          key: const Key('face-crop-assigned-empty'),
                        ),
                )
              : _AppearanceGrid(
                  appearances: detail.appearances,
                  source: FaceCropTray.assigned,
                  busy: _busy || controller.isBusy,
                  onOpenItem: _openItem,
                ),
        );
      },
    );
  }
}

class _PersonChrome extends StatelessWidget {
  const _PersonChrome({
    required this.detail,
    required this.controller,
    required this.renameController,
    required this.renaming,
    required this.busy,
    required this.onStartRename,
    required this.onDoneRename,
    required this.onCancelRename,
    required this.onSave,
    required this.onDelete,
  });

  final PersonDetail detail;
  final PersonDetailController controller;
  final TextEditingController renameController;
  final bool renaming;
  final bool busy;
  final VoidCallback onStartRename;
  final Future<void> Function() onDoneRename;
  final VoidCallback onCancelRename;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  bool get _isUnnamed =>
      detail.name == null || detail.name!.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('face-crop-person-chrome'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: renaming || _isUnnamed
                  ? TextField(
                      key: const Key('face-crop-person-rename'),
                      controller: renameController,
                      enabled: !busy,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => onDoneRename(),
                    )
                  : Text(
                      detail.name!,
                      key: const Key('face-crop-person-name'),
                      style: Theme.of(context).textTheme.titleSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(width: 8),
            LinkStateBadge(linkState: detail.linkState),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            if (renaming || _isUnnamed)
              TextButton(
                key: const Key('face-crop-person-rename-done'),
                onPressed: busy ? null : onDoneRename,
                child: const Text('Done'),
              )
            else
              TextButton(
                key: const Key('face-crop-person-rename-start'),
                onPressed: busy ? null : onStartRename,
                child: const Text('Rename'),
              ),
            if (renaming)
              TextButton(
                key: const Key('face-crop-person-rename-cancel'),
                onPressed: busy ? null : onCancelRename,
                child: const Text('Cancel'),
              ),
            if (controller.canConfirm)
              TextButton(
                key: const Key('face-crop-person-save'),
                onPressed: busy ? null : onSave,
                child: const Text('Save'),
              ),
            if (controller.canDelete)
              TextButton(
                key: const Key('face-crop-person-delete'),
                onPressed: busy ? null : onDelete,
                child: const Text('Delete'),
              ),
          ],
        ),
      ],
    );
  }
}

class _TrayColumn extends StatelessWidget {
  const _TrayColumn({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onAccept,
    required this.child,
    this.header,
  });

  final String title;
  final String subtitle;
  final Future<void> Function(FaceCropDragData data) onAccept;
  final Widget child;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<FaceCropDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidate, rejected) {
        final hovering = candidate.isNotEmpty;
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: hovering ? scheme.primary : scheme.outlineVariant,
              width: hovering ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: hovering
                ? scheme.primaryContainer.withValues(alpha: 0.25)
                : scheme.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (header != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: header,
                ),
              const Divider(height: 16),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

Widget _appearanceThumb(PersonAppearance a, {bool fill = false, double size = 72}) {
  final itemId = a.itemId;
  final tagId = a.tagId;
  if (itemId == null) {
    return Icon(Icons.person_outline, size: fill ? 28 : size * 0.45);
  }
  if (a.region != null) {
    return WhoExclusionCropThumb(
      itemId: itemId,
      region: a.region!,
      size: size,
      fill: fill,
      tooltip: 'Who face',
    );
  }
  if (tagId != null) {
    return WhoFaceCropThumb(
      itemId: itemId,
      tagId: tagId,
      region: a.region,
      size: size,
      fill: fill,
    );
  }
  return Icon(Icons.person_outline, size: fill ? 28 : size * 0.45);
}

class _AppearanceGrid extends StatelessWidget {
  const _AppearanceGrid({
    required this.appearances,
    required this.source,
    required this.busy,
    required this.onOpenItem,
  });

  final List<PersonAppearance> appearances;
  final FaceCropTray source;
  final bool busy;
  final void Function(String itemId) onOpenItem;

  @override
  Widget build(BuildContext context) {
    if (appearances.isEmpty) {
      return const Center(child: Text('No crops'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: appearances.length,
      itemBuilder: (context, index) {
        final a = appearances[index];
        final itemId = a.itemId;
        final tagId = a.tagId;
        final canDrag = !busy && itemId != null && tagId != null;
        // Fixed size (same as person detail) — fill+expand inside Material/InkWell
        // often got zero constraints and painted only the grey placeholder.
        final thumb = _appearanceThumb(a, size: 72);
        final tile = Material(
          key: Key('face-crop-appearance-${a.id}'),
          color: Colors.transparent,
          child: InkWell(
            onTap: busy || itemId == null ? null : () => onOpenItem(itemId),
            child: Center(child: thumb),
          ),
        );
        if (!canDrag) return tile;
        final data = FaceCropDragData.appearance(
          source: source,
          appearanceId: a.id,
          itemId: itemId,
          tagId: tagId,
          personId: a.personId,
          region: a.region,
        );
        return Draggable<FaceCropDragData>(
          data: data,
          feedback: Material(
            elevation: 4,
            child: SizedBox(
              width: 72,
              height: 72,
              child: _appearanceThumb(a, size: 72),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: tile,
        );
      },
    );
  }
}

class _ExclusionGrid extends StatelessWidget {
  const _ExclusionGrid({
    required this.exclusions,
    required this.busy,
    required this.onOpenItem,
  });

  final List<WhoExclusion> exclusions;
  final bool busy;
  final void Function(String itemId) onOpenItem;

  @override
  Widget build(BuildContext context) {
    if (exclusions.isEmpty) {
      return const Center(child: Text('No excluded crops'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: exclusions.length,
      itemBuilder: (context, index) {
        final e = exclusions[index];
        final thumb = WhoExclusionCropThumb(
          itemId: e.itemId,
          region: e.region,
          size: 72,
        );
        final tile = Material(
          key: Key('face-crop-exclusion-${e.id}'),
          color: Colors.transparent,
          child: InkWell(
            onTap: busy ? null : () => onOpenItem(e.itemId),
            child: Center(child: thumb),
          ),
        );
        if (busy) return tile;
        final data = FaceCropDragData.exclusion(
          source: FaceCropTray.excluded,
          exclusionId: e.id,
          itemId: e.itemId,
          region: e.region,
          createdFromTagId: e.createdFromTagId,
        );
        return Draggable<FaceCropDragData>(
          data: data,
          feedback: Material(
            elevation: 4,
            child: SizedBox(
              width: 72,
              height: 72,
              child: WhoExclusionCropThumb(
                itemId: e.itemId,
                region: e.region,
                size: 72,
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: tile),
          child: tile,
        );
      },
    );
  }
}

/// Navigate to the face-crop trays workspace (optionally focused on a person).
Future<void> openFaceCropTrays(
  BuildContext context, {
  String? personId,
}) async {
  final container = ProviderScope.containerOf(context);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => SelectableScope(
        child: UncontrolledProviderScope(
          container: container,
          child: FaceCropTraysPage(initialPersonId: personId),
        ),
      ),
    ),
  );
}
