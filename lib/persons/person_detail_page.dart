import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/link_state_view.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';

/// Person detail + confirm / split / unlink / reassign / rename (D9).
///
/// Never displays likeness vectors (R1). Every merge has a visible undo path
/// via unlink / split / reassign (R6).
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
      _renameController.text = detail.name ?? '';
    });
  }

  Future<void> _saveRename(PersonDetailController controller) async {
    await controller.rename(_renameController.text);
    if (mounted) {
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
              if (controller.canConfirm)
                TextButton(
                  key: const Key('person-confirm'),
                  onPressed: () => controller.confirm(),
                  child: const Text('Confirm'),
                ),
            ],
          ),
          body: _buildBody(controller),
        );
      },
    );
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
                detail.name ?? '(unnamed)',
                key: const Key('person-detail-name'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            LinkStateBadge(linkState: detail.linkState),
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
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('person-rename-save'),
                onPressed: controller.isBusy
                    ? null
                    : () => _saveRename(controller),
                child: const Text('Save'),
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
          OutlinedButton(
            key: const Key('person-rename'),
            onPressed: controller.isBusy ? null : () => _startRename(detail),
            child: const Text('Rename person'),
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
              onUnlink: () => controller.unlink(appearance.id),
              onSplit: () => controller.split([appearance.id]),
              onReassign: () {
                final target = _reassignTarget[appearance.id];
                if (target == null || target.isEmpty) return;
                controller.reassign(appearance.id, target);
              },
            ),
      ],
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard({
    required this.appearance,
    required this.otherPersons,
    required this.busy,
    required this.reassignTarget,
    required this.onReassignTargetChanged,
    required this.onUnlink,
    required this.onSplit,
    required this.onReassign,
  });

  final PersonAppearance appearance;
  final List<Person> otherPersons;
  final bool busy;
  final String reassignTarget;
  final ValueChanged<String> onReassignTargetChanged;
  final VoidCallback onUnlink;
  final VoidCallback onSplit;
  final VoidCallback onReassign;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        key: Key('appearance-card-${appearance.id}'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'appearance ${appearance.id}',
                  key: Key('appearance-id-${appearance.id}'),
                ),
              ),
              LinkStateBadge(linkState: appearance.linkState),
            ],
          ),
          if (appearance.itemId != null)
            Text(
              'item ${appearance.itemId}',
              key: Key('appearance-item-${appearance.id}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (appearance.keyPeriodId != null)
            Text(
              'key period ${appearance.keyPeriodId}',
              key: Key('appearance-key-period-${appearance.id}'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: Key('appearance-unlink-${appearance.id}'),
                onPressed: busy ? null : onUnlink,
                child: const Text('Unlink'),
              ),
              OutlinedButton(
                key: Key('appearance-split-${appearance.id}'),
                onPressed: busy ? null : onSplit,
                child: const Text('Split'),
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
                    for (final person in otherPersons)
                      DropdownMenuItem(
                        value: person.id,
                        child: Text(person.name ?? person.id),
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
