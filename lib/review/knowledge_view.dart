import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_edits.dart';
import 'package:tagkin_desktop/persons/person_assign_control.dart';
import 'package:tagkin_desktop/persons/who_exclusion_crop_thumb.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';

/// Per-crop / whole-item assign in a two-column grid, plus excluded-face thumbs.
class KnowledgeView extends StatelessWidget {
  const KnowledgeView({
    super.key,
    required this.knowledge,
    this.itemId,
    this.personNamesById = const {},
    this.persons = const [],
    this.assignEnabled = true,
    this.cropIntents = const {},
    this.appearanceIntents = const {},
    this.pendingItemAssigns = const [],
    this.onPersonTap,
    this.onAssignCrop,
    this.onAssignItem,
    this.onReassignAppearance,
    this.onUnassign,
    this.onExcludeCrop,
    this.onRemovePendingItemAssign,
  });

  final ItemKnowledge knowledge;
  final String? itemId;
  final Map<String, String> personNamesById;
  final List<Person> persons;
  final bool assignEnabled;
  final Map<String, PersonAssignIntent> cropIntents;
  final Map<String, PersonAssignIntent> appearanceIntents;
  final List<PersonAssignIntent> pendingItemAssigns;
  final void Function(String personId)? onPersonTap;
  final Future<void> Function(
    String tagId, {
    String? personId,
    String? name,
  })? onAssignCrop;
  final Future<void> Function({
    String? personId,
    String? name,
  })? onAssignItem;
  final Future<void> Function(
    String appearanceId, {
    String? personId,
    String? name,
  })? onReassignAppearance;
  final Future<void> Function(String appearanceId)? onUnassign;
  final Future<void> Function(String tagId)? onExcludeCrop;
  final void Function(int index)? onRemovePendingItemAssign;

  @override
  Widget build(BuildContext context) {
    final crops = whoFaceCropTags(knowledge);
    final itemAssignments = itemLevelPersonAssignments(knowledge);
    final cells = <Widget>[];
    if (crops.isNotEmpty) {
      for (final tag in crops) {
        if (cropIntents[tag.id]?.exclude == true) continue;
        cells.add(
          _CropAssignRow(
            tag: tag,
            knowledge: knowledge,
            itemId: itemId,
            persons: persons,
            personNamesById: personNamesById,
            intent: cropIntents[tag.id],
            enabled: assignEnabled,
            onPersonTap: onPersonTap,
            onAssignCrop: onAssignCrop,
            onUnassign: onUnassign,
            onExcludeCrop: onExcludeCrop,
          ),
        );
      }
    } else {
      for (final appearance in itemAssignments) {
        cells.add(
          _ItemAssignRow(
            appearance: appearance,
            personNamesById: personNamesById,
            persons: persons,
            intent: appearanceIntents[appearance.id],
            enabled: assignEnabled,
            onPersonTap: onPersonTap,
            onReassignAppearance: onReassignAppearance,
            onUnassign: onUnassign,
          ),
        );
      }
      for (var i = 0; i < pendingItemAssigns.length; i++) {
        final intent = pendingItemAssigns[i];
        cells.add(
          _PendingItemAssignRow(
            index: i,
            intent: intent,
            enabled: assignEnabled,
            onRemove: onRemovePendingItemAssign,
          ),
        );
      }
      if (onAssignItem != null) {
        cells.add(
          PersonAssignControl(
            key: const Key('item-assign-person'),
            persons: persons,
            enabled: assignEnabled,
            label: itemAssignments.isEmpty && pendingItemAssigns.isEmpty
                ? 'Assign to person'
                : 'Assign another person',
            onAssign: ({personId, name}) =>
                onAssignItem!(personId: personId, name: name),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (cells.isNotEmpty) _TwoColumnGrid(cells: cells),
      ],
    );
  }
}

/// Excluded-face crop thumbs (full width, below face-person grid).
class ExcludedFacesStrip extends StatelessWidget {
  const ExcludedFacesStrip({
    super.key,
    required this.knowledge,
    this.draftExcludedCrops = const [],
  });

  final ItemKnowledge knowledge;
  final List<Tag> draftExcludedCrops;

  @override
  Widget build(BuildContext context) {
    if (knowledge.whoExclusions.isEmpty && draftExcludedCrops.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Excluded faces',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final exclusion in knowledge.whoExclusions)
              WhoExclusionCropThumb(
                key: Key('who-exclusion-${exclusion.id}'),
                itemId: exclusion.itemId,
                region: exclusion.region,
                item: knowledge.item,
                size: 40,
              ),
            for (final tag in draftExcludedCrops)
              if (tag.region != null)
                WhoExclusionCropThumb(
                  key: Key('who-exclusion-draft-${tag.id}'),
                  itemId: knowledge.item.id,
                  region: tag.region!,
                  item: knowledge.item,
                  size: 40,
                ),
          ],
        ),
      ],
    );
  }
}

class _TwoColumnGrid extends StatelessWidget {
  const _TwoColumnGrid({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCols = constraints.maxWidth >= 640;
        if (!twoCols) {
          return Column(
            key: const Key('item-face-assign-grid'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final cell in cells)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: cell,
                ),
            ],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < cells.length; i += 2) {
          rows.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cells[i]),
                  const SizedBox(width: 24),
                  Expanded(
                    child:
                        i + 1 < cells.length ? cells[i + 1] : const SizedBox(),
                  ),
                ],
              ),
            ),
          );
        }
        return Column(
          key: const Key('item-face-assign-grid'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

({String? personId, String? personName, bool unassign}) _effectivePerson({
  required PersonAssignIntent? intent,
  required String? baselinePersonId,
  required Map<String, String> personNamesById,
}) {
  if (intent != null) {
    if (intent.unassign) {
      return (personId: null, personName: null, unassign: true);
    }
    if (intent.name != null && intent.name!.trim().isNotEmpty) {
      return (
        personId: intent.personId,
        personName: intent.name!.trim(),
        unassign: false,
      );
    }
    if (intent.personId != null) {
      return (
        personId: intent.personId,
        personName: personNamesById[intent.personId]?.trim(),
        unassign: false,
      );
    }
  }
  final id = baselinePersonId;
  return (
    personId: id,
    personName: id != null ? personNamesById[id]?.trim() : null,
    unassign: false,
  );
}

class _CropAssignRow extends StatelessWidget {
  const _CropAssignRow({
    required this.tag,
    required this.knowledge,
    this.itemId,
    required this.persons,
    required this.personNamesById,
    this.intent,
    required this.enabled,
    this.onPersonTap,
    this.onAssignCrop,
    this.onUnassign,
    this.onExcludeCrop,
  });

  final Tag tag;
  final ItemKnowledge knowledge;
  final String? itemId;
  final List<Person> persons;
  final Map<String, String> personNamesById;
  final PersonAssignIntent? intent;
  final bool enabled;
  final void Function(String personId)? onPersonTap;
  final Future<void> Function(
    String tagId, {
    String? personId,
    String? name,
  })? onAssignCrop;
  final Future<void> Function(String appearanceId)? onUnassign;
  final Future<void> Function(String tagId)? onExcludeCrop;

  @override
  Widget build(BuildContext context) {
    final appearance = appearanceForWhoTag(knowledge, tag.id);
    final effective = _effectivePerson(
      intent: intent,
      baselinePersonId: appearance?.personId,
      personNamesById: personNamesById,
    );
    final personId = effective.personId;
    final personName = effective.personName;
    final named = personName != null && personName.isNotEmpty;
    final whoLabel = tag.value.trim();
    final label = [
      if (named) personName,
      if (whoLabel.isNotEmpty) whoLabel,
      if (!named && whoLabel.isEmpty) 'Unnamed',
    ].join(' ');
    final cropItemId = appearance?.itemId ?? itemId;
    final canUnassign = appearance?.id != null &&
        personId != null &&
        onUnassign != null &&
        !effective.unassign;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (cropItemId != null) ...[
            WhoFaceCropThumb(
              itemId: cropItemId,
              tagId: tag.id,
              knowledge: knowledge,
              size: 40,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (personId != null && onPersonTap != null)
                  InkWell(
                    key: Key('appearance-person-link-${appearance?.id}'),
                    onTap: () => onPersonTap!(personId),
                    child: Text(
                      label,
                      key: Key('appearance-crop-${tag.id}'),
                    ),
                  )
                else
                  Text(
                    label,
                    key: Key('appearance-crop-${tag.id}'),
                  ),
                if (onAssignCrop != null) ...[
                  const SizedBox(height: 6),
                  PersonAssignControl(
                    key: Key('item-assign-face-${tag.id}'),
                    persons: persons,
                    currentPersonId: personId,
                    enabled: enabled,
                    label: named ? 'Reassign' : 'Assign',
                    onAssign: ({personId, name}) => onAssignCrop!(
                      tag.id,
                      personId: personId,
                      name: name,
                    ),
                  ),
                ],
                if (canUnassign || onExcludeCrop != null)
                  Wrap(
                    spacing: 8,
                    children: [
                      if (canUnassign)
                        TextButton(
                          key: Key('item-unassign-${appearance!.id}'),
                          onPressed: enabled
                              ? () => onUnassign!(appearance.id)
                              : null,
                          child: const Text('Unassign'),
                        ),
                      if (onExcludeCrop != null)
                        TextButton(
                          key: Key('item-exclude-face-${tag.id}'),
                          onPressed:
                              enabled ? () => onExcludeCrop!(tag.id) : null,
                          child: const Text('Exclude from photo'),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemAssignRow extends StatelessWidget {
  const _ItemAssignRow({
    required this.appearance,
    required this.personNamesById,
    required this.persons,
    this.intent,
    required this.enabled,
    this.onPersonTap,
    this.onReassignAppearance,
    this.onUnassign,
  });

  final PersonAppearance appearance;
  final Map<String, String> personNamesById;
  final List<Person> persons;
  final PersonAssignIntent? intent;
  final bool enabled;
  final void Function(String personId)? onPersonTap;
  final Future<void> Function(
    String appearanceId, {
    String? personId,
    String? name,
  })? onReassignAppearance;
  final Future<void> Function(String appearanceId)? onUnassign;

  @override
  Widget build(BuildContext context) {
    final effective = _effectivePerson(
      intent: intent,
      baselinePersonId: appearance.personId,
      personNamesById: personNamesById,
    );
    final personId = effective.personId;
    final name = effective.personName ??
        (personId != null ? 'Person' : 'Unassigned');
    final canUnassign =
        personId != null && onUnassign != null && !effective.unassign;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: personId != null && onPersonTap != null
                ? InkWell(
                    key: Key('appearance-person-link-${appearance.id}'),
                    onTap: () => onPersonTap!(personId),
                    child: Text(
                      name,
                      key: Key('appearance-${appearance.id}'),
                    ),
                  )
                : Text(
                    name,
                    key: Key('appearance-${appearance.id}'),
                  ),
          ),
          if (onReassignAppearance != null)
            SizedBox(
              width: 220,
              child: PersonAssignControl(
                key: Key('item-reassign-${appearance.id}'),
                persons: persons,
                currentPersonId: personId,
                enabled: enabled,
                label: 'Reassign',
                onAssign: ({personId, name}) => onReassignAppearance!(
                  appearance.id,
                  personId: personId,
                  name: name,
                ),
              ),
            ),
          if (canUnassign)
            TextButton(
              key: Key('item-unassign-${appearance.id}'),
              onPressed: enabled ? () => onUnassign!(appearance.id) : null,
              child: const Text('Unassign'),
            ),
        ],
      ),
    );
  }
}

class _PendingItemAssignRow extends StatelessWidget {
  const _PendingItemAssignRow({
    required this.index,
    required this.intent,
    required this.enabled,
    this.onRemove,
  });

  final int index;
  final PersonAssignIntent intent;
  final bool enabled;
  final void Function(int index)? onRemove;

  @override
  Widget build(BuildContext context) {
    final label = intent.name?.trim().isNotEmpty == true
        ? intent.name!.trim()
        : 'Person';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              key: Key('item-pending-assign-$index'),
            ),
          ),
          if (onRemove != null)
            TextButton(
              key: Key('item-pending-assign-remove-$index'),
              onPressed: enabled ? () => onRemove!(index) : null,
              child: const Text('Unassign'),
            ),
        ],
      ),
    );
  }
}
