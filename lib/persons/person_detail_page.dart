import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/confirm_remove_person_dialog.dart';
import 'package:tagkin_desktop/persons/face_crop_trays_page.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';
import 'package:tagkin_desktop/persons/person_name.dart';
import 'package:tagkin_desktop/persons/person_name_collision_dialog.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';

/// Person detail + unassign / reassign / rename / delete (D9).
///
/// Never displays likeness vectors (R1). Every merge has a visible undo path
/// via unassign / reassign (R6).
class PersonDetailPage extends ConsumerStatefulWidget {
  const PersonDetailPage({super.key, required this.personId});

  final String personId;

  @override
  ConsumerState<PersonDetailPage> createState() => _PersonDetailPageState();
}

class _PersonDetailPageState extends ConsumerState<PersonDetailPage> {
  final _renameController = TextEditingController();
  bool _renaming = false;
  final Map<String, String> _reassignTarget = {};
  final UndoController _undoStack = UndoController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(personDetailControllerProvider(widget.personId)).load();
    });
  }

  @override
  void dispose() {
    _renameController.dispose();
    _undoStack.dispose();
    super.dispose();
  }

  void _startRename(PersonDetail detail) {
    setState(() {
      _renaming = true;
      _renameController.text = detail.name;
    });
  }

  Future<void> _saveRename(PersonDetailController controller) async {
    final prior = controller.detail?.name;
    if (prior == null) return;
    final next = _renameController.text.trim();
    if (next == prior) {
      if (mounted) setState(() => _renaming = false);
      return;
    }
    final clash = findPersonByName(
      controller.otherPersons,
      next,
      excludeId: controller.personId,
    );
    if (clash != null) {
      final choice = await showPersonNameCollisionDialog(
        context,
        existingName: clash.name,
        mergeLabel: 'Merge this person into them',
      );
      if (choice != PersonNameCollisionChoice.merge || !mounted) return;
      await ref.read(personsRepositoryProvider).mergePerson(
            controller.personId,
            clash.id,
          );
      if (!mounted) return;
      ref.read(collectionsControllerProvider).markDirty();
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    final ok = await controller.rename(_renameController.text);
    if (mounted && ok) {
      ref.read(collectionsControllerProvider).markDirty();
      setState(() => _renaming = false);
      _undoStack.push(
        CallbackUndoableAction(
          label: 'Rename person',
          onUndo: () async {
            final restored = await controller.rename(prior);
            if (restored && mounted) {
              ref.read(collectionsControllerProvider).markDirty();
            }
          },
          onRedo: () async {
            final restored = await controller.rename(next);
            if (restored && mounted) {
              ref.read(collectionsControllerProvider).markDirty();
            }
          },
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller =
        ref.watch(personDetailControllerProvider(widget.personId));

    return ActiveUndoHost(
      controller: _undoStack,
      child: UndoShortcuts(
      controller: _undoStack,
      onError: (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      },
      child: ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('Person'),
                const SizedBox(width: 8),
                UndoDepthBadge(controller: _undoStack),
              ],
            ),
            actions: [
              if (controller.canUnassign)
                Tooltip(
                  message:
                      'Remove this person. Faces move to Unassigned. '
                      'Use Unassign on a face to detach only that face.',
                  child: TextButton(
                    key: const Key('person-unassign'),
                    onPressed: () => _confirmRemovePerson(controller),
                    child: const Text('Remove'),
                  ),
                ),
              TextButton(
                key: const Key('person-open-trays'),
                onPressed: () => openFaceCropTrays(
                  context,
                  personId: widget.personId,
                ),
                child: const Text('Faces'),
              ),
            ],
          ),
          body: _buildBody(controller),
        );
      },
    ),
    ),
    );
  }

  Future<void> _confirmRemovePerson(PersonDetailController controller) async {
    final confirmed = await confirmRemovePerson(
      context: context,
      confirmKey: const Key('person-unassign-confirm'),
      body:
          'Removes this person. Its faces move to Unassigned '
          'so you can assign them again. To detach one face only, '
          'use Unassign on that face.',
    );
    if (!confirmed || !mounted) return;
    final ok = await controller.unassignPerson();
    if (ok && mounted) {
      ref.read(collectionsControllerProvider).markDirty();
      Navigator.of(context).pop();
    }
  }

  Widget _buildBody(PersonDetailController controller) {
    if (controller.phase == PersonDetailPhase.loading ||
        controller.phase == PersonDetailPhase.idle) {
      return const Center(
        child: CircularProgressIndicator(key: Key('person-detail-loading')),
      );
    }

    if (controller.phase == PersonDetailPhase.error &&
        controller.detail == null) {
      final error = controller.error!;
      final isNotFound =
          error is ApiException && error.statusCode == 404;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isNotFound
                    ? 'Person not found'
                    : 'Could not load person: $error',
                key: isNotFound
                    ? const Key('person-detail-not-found')
                    : const Key('person-detail-error'),
                textAlign: TextAlign.center,
              ),
              if (!isNotFound) ...[
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('person-detail-retry'),
                  onPressed: () => controller.load(),
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final detail = controller.detail!;
    return ListView(
      key: const Key('person-detail'),
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                detail.name,
                key: const Key('person-detail-name'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          detail.id,
          key: const Key('person-detail-id'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (_renaming)
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('person-rename-field'),
                  controller: _renameController,
                  decoration: const InputDecoration(
                    labelText: 'Person name',
                    border: OutlineInputBorder(),
                  ),
                  enabled: !controller.isBusy,
                  onSubmitted: controller.isBusy
                      ? null
                      : (_) => _saveRename(controller),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('person-rename-done'),
                onPressed: controller.isBusy
                    ? null
                    : () => _saveRename(controller),
                child: const Text('Done'),
              ),
              TextButton(
                key: const Key('person-rename-cancel'),
                onPressed: controller.isBusy
                    ? null
                    : () => setState(() => _renaming = false),
                child: const Text('Cancel'),
              ),
            ],
          )
        else
          Tooltip(
            message: 'Change this person’s name',
            child: OutlinedButton(
              key: const Key('person-rename'),
              onPressed: controller.isBusy ? null : () => _startRename(detail),
              child: const Text('Rename person'),
            ),
          ),
        if (controller.error != null &&
            controller.phase == PersonDetailPhase.error) ...[
          const SizedBox(height: 12),
          Text(
            '${controller.error}',
            key: const Key('person-action-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          'Appearances',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (detail.appearances.isEmpty)
          const Text(
            'No appearances linked to this person.',
            key: Key('person-appearances-empty'),
          )
        else
          for (final appearance in detail.appearances)
            _AppearanceCard(
              appearance: appearance,
              otherPersons: controller.otherPersons,
              busy: controller.isBusy,
              reassignTarget: _reassignTarget[appearance.id] ?? '',
              onReassignTargetChanged: (value) {
                setState(() => _reassignTarget[appearance.id] = value);
              },
              onUnassign: () async {
                final appearanceId = appearance.id;
                final fromPersonId = widget.personId;
                await controller.unlink(appearanceId);
                if (mounted && controller.error == null) {
                  ref.read(collectionsControllerProvider).markDirty();
                  _undoStack.push(
                    CallbackUndoableAction(
                      label: 'Unassign appearance',
                      onUndo: () async {
                        await controller.reassign(
                          appearanceId,
                          personId: fromPersonId,
                        );
                        if (mounted && controller.error == null) {
                          ref.read(collectionsControllerProvider).markDirty();
                        }
                      },
                      onRedo: () async {
                        await controller.unlink(appearanceId);
                        if (mounted && controller.error == null) {
                          ref.read(collectionsControllerProvider).markDirty();
                        }
                      },
                    ),
                  );
                }
              },
              onOpenItem: appearance.itemId == null
                  ? null
                  : () => _openItem(appearance.itemId!),
              onExclude: appearance.itemId == null || appearance.tagId == null
                  ? null
                  : () => _excludeAppearance(
                        appearance.itemId!,
                        appearance.tagId!,
                      ),
              onReassign: () async {
                final target = _reassignTarget[appearance.id];
                if (target == null || target.isEmpty) return;
                final appearanceId = appearance.id;
                final fromPersonId = widget.personId;
                String? newPersonName;
                String? targetPersonId;
                if (target == _AppearanceCard.newPersonSentinel) {
                  var typed = await showPersonNameDialog(context);
                  while (typed != null && mounted) {
                    final clash = findPersonByName(
                      [
                        ...controller.otherPersons,
                        if (controller.detail != null)
                          Person(
                            id: controller.detail!.id,
                            name: controller.detail!.name,
                            createdAt: controller.detail!.createdAt,
                          ),
                      ],
                      typed,
                    );
                    if (clash == null) {
                      newPersonName = typed;
                      break;
                    }
                    if (!mounted) return;
                    final choice = await showPersonNameCollisionDialog(
                      context,
                      existingName: clash.name,
                      mergeLabel: 'Merge this face into them',
                    );
                    if (choice == PersonNameCollisionChoice.merge) {
                      targetPersonId = clash.id;
                      break;
                    }
                    if (!mounted) return;
                    typed = await showPersonNameDialog(
                      context,
                      initialName: typed,
                    );
                  }
                  if ((newPersonName == null && targetPersonId == null) ||
                      !mounted) {
                    return;
                  }
                } else {
                  targetPersonId = target;
                }
                await controller.reassign(
                  appearanceId,
                  personId: targetPersonId,
                  name: newPersonName,
                );
                if (mounted && controller.error == null) {
                  ref.read(collectionsControllerProvider).markDirty();
                  _undoStack.push(
                    CallbackUndoableAction(
                      label: 'Reassign appearance',
                      onUndo: () async {
                        await controller.reassign(
                          appearanceId,
                          personId: fromPersonId,
                        );
                        if (mounted && controller.error == null) {
                          ref.read(collectionsControllerProvider).markDirty();
                        }
                      },
                      onRedo: () async {
                        await controller.reassign(
                          appearanceId,
                          personId: targetPersonId,
                          name: newPersonName,
                        );
                        if (mounted && controller.error == null) {
                          ref.read(collectionsControllerProvider).markDirty();
                        }
                      },
                    ),
                  );
                }
              },
            ),
      ],
    );
  }

  Future<void> _openItem(String itemId) async {
    final container = ProviderScope.containerOf(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UndoSelectableRoute(
          child: UncontrolledProviderScope(
            container: container,
            child: ItemDetailPage(itemId: itemId),
          ),
        ),
      ),
    );
  }

  Future<void> _excludeAppearance(String itemId, String tagId) async {
    final controller =
        ref.read(personDetailControllerProvider(widget.personId));
    try {
      await ref.read(itemsRepositoryProvider).createWhoExclusion(itemId, tagId);
      if (!mounted) return;
      await controller.load();
      if (!mounted) return;
      ref.read(collectionsControllerProvider).markDirty();
      if (controller.detail == null) {
        Navigator.of(context).pop();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          key: Key('person-exclude-done'),
          content: Text(
            'Excluded from this photo — will stay out on re-analyze',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('person-exclude-error'),
          content: Text('Exclude failed: $e'),
        ),
      );
    }
  }
}
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.appearance,
    required this.otherPersons,
    required this.busy,
    required this.reassignTarget,
    required this.onReassignTargetChanged,
    required this.onUnassign,
    required this.onReassign,
    this.onOpenItem,
    this.onExclude,
  });

  /// Sentinel dropdown value: create a new person, then assign.
  static const newPersonSentinel = '__new_person__';

  final PersonAppearance appearance;
  final List<Person> otherPersons;
  final bool busy;
  final String reassignTarget;
  final ValueChanged<String> onReassignTargetChanged;
  final VoidCallback onUnassign;
  final VoidCallback onReassign;
  final VoidCallback? onOpenItem;
  final VoidCallback? onExclude;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        key: Key('appearance-card-${appearance.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (appearance.itemId != null && appearance.tagId != null)
                InkWell(
                  key: Key('appearance-open-item-${appearance.id}'),
                  onTap: busy ? null : onOpenItem,
                  child: WhoFaceCropThumb(
                    itemId: appearance.itemId!,
                    tagId: appearance.tagId!,
                    region: appearance.region,
                    size: 72,
                  ),
                )
              else if (appearance.itemId != null)
                Text(
                  'This photo',
                  key: Key('appearance-item-level-${appearance.id}'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onOpenItem != null)
                OutlinedButton(
                  key: Key('appearance-open-photo-${appearance.id}'),
                  onPressed: busy ? null : onOpenItem,
                  child: const Text('Open photo'),
                ),
              if (onExclude != null)
                OutlinedButton(
                  key: Key('appearance-exclude-${appearance.id}'),
                  onPressed: busy ? null : onExclude,
                  child: const Text('Exclude from photo'),
                ),
              OutlinedButton(
                key: Key('appearance-unassign-${appearance.id}'),
                onPressed: busy ? null : onUnassign,
                child: const Text('Unassign'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: Key('appearance-reassign-select-${appearance.id}'),
                  // ignore: deprecated_member_use — value is stable across Flutter versions
                  value: reassignTarget.isEmpty ? null : reassignTarget,
                  decoration: const InputDecoration(
                    labelText: 'Reassign to person',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: newPersonSentinel,
                      child: Text('New person'),
                    ),
                    for (final person in otherPersons)
                      DropdownMenuItem(
                        value: person.id,
                        child: Text(person.name),
                      ),
                  ],
                  onChanged: busy
                      ? null
                      : (value) {
                          if (value != null) onReassignTargetChanged(value);
                        },
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: Key('appearance-reassign-${appearance.id}'),
                onPressed:
                    busy || reassignTarget.isEmpty ? null : onReassign,
                child: const Text('Reassign'),
              ),
            ],
          ),
          const Divider(height: 24),
        ],
      ),
    );
  }
}
