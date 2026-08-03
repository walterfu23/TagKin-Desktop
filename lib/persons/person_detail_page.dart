import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_page.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/face_crop_trays_page.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';
import 'package:tagkin_desktop/persons/person_name_dialog.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

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
    super.dispose();
  }

  void _startRename(PersonDetail detail) {
    setState(() {
      _renaming = true;
      _renameController.text = detail.name;
    });
  }

  Future<void> _saveRename(PersonDetailController controller) async {
    final ok = await controller.rename(_renameController.text);
    if (mounted && ok) {
      ref.read(collectionsControllerProvider).markDirty();
      setState(() => _renaming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller =
        ref.watch(personDetailControllerProvider(widget.personId));

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Person'),
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
    );
  }

  Future<void> _confirmRemovePerson(PersonDetailController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove person?'),
        content: const Text(
          'Removes this person. Its faces move to Unassigned '
          'so you can assign them again. To detach one face only, '
          'use Unassign on that face.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('person-unassign-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
                await controller.unlink(appearance.id);
                if (mounted && controller.error == null) {
                  ref.read(collectionsControllerProvider).markDirty();
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
                if (target == _AppearanceCard.newPersonSentinel) {
                  final name = await showPersonNameDialog(context);
                  if (name == null || !mounted) return;
                  await controller.reassign(appearance.id, name: name);
                } else {
                  await controller.reassign(appearance.id, personId: target);
                }
                if (mounted && controller.error == null) {
                  ref.read(collectionsControllerProvider).markDirty();
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
        builder: (_) => SelectableScope(
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
              if (appearance.itemId != null && appearance.tagId != null) ...[
                InkWell(
                  key: Key('appearance-open-item-${appearance.id}'),
                  onTap: busy ? null : onOpenItem,
                  child: WhoFaceCropThumb(
                    itemId: appearance.itemId!,
                    tagId: appearance.tagId!,
                    region: appearance.region,
                    size: 72,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'appearance ${appearance.id}',
                      key: Key('appearance-id-${appearance.id}'),
                    ),
                    if (appearance.itemId != null)
                      Text(
                        'item ${appearance.itemId}',
                        key: Key('appearance-item-${appearance.id}'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (appearance.tagId != null)
                      Text(
                        'who tag ${appearance.tagId}',
                        key: Key('appearance-tag-${appearance.id}'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (appearance.keyPeriodId != null)
                      Text(
                        'key period ${appearance.keyPeriodId}',
                        key: Key('appearance-key-period-${appearance.id}'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
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
