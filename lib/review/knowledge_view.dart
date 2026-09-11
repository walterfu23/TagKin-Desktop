import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_edits.dart';
import 'package:tagkin_desktop/persons/face_crop/face_crop_tap.dart';
import 'package:tagkin_desktop/persons/person_assign_control.dart';
import 'package:tagkin_desktop/persons/who_exclusion_crop_thumb.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/ui/alpha_order.dart';

const double _kFaceThumbSize = 72;
const double _kFaceCellWidth = 96;

/// Per-crop / whole-item assign, plus excluded-face thumbs.
/// Face crops sit in a compact thumb+name grid; tap selects, double-click an
/// assigned face opens that person.
class KnowledgeView extends StatefulWidget {
  const KnowledgeView({
    super.key,
    required this.knowledge,
    this.itemId,
    this.personNamesById = const {},
    this.persons = const [],
    this.assignEnabled = true,
    this.cropIntents = const {},
    this.appearanceIntents = const {},
    this.exclusionIntents = const {},
    this.pendingItemAssigns = const [],
    this.onPersonTap,
    this.onAssignCrop,
    this.onAssignItem,
    this.onReassignAppearance,
    this.onUnassign,
    this.onExcludeCrop,
    this.onAssignIncludedExclusion,
    this.onExcludeIncludedExclusion,
    this.onRemovePendingItemAssign,
    this.cropTags,
    this.includeIncludedExclusions = true,
    this.allowItemAssign = true,
    this.faceGridKey = const Key('item-face-assign-grid'),
    this.faceHintKey = const Key('item-face-hint'),
  });

  final ItemKnowledge knowledge;
  final String? itemId;
  final Map<String, String> personNamesById;
  final List<Person> persons;
  final bool assignEnabled;
  final Map<String, PersonAssignIntent> cropIntents;
  final Map<String, PersonAssignIntent> appearanceIntents;
  final Map<String, PersonAssignIntent> exclusionIntents;
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
  final Future<void> Function(
    String exclusionId, {
    String? personId,
    String? name,
  })? onAssignIncludedExclusion;
  final Future<void> Function(String exclusionId)? onExcludeIncludedExclusion;
  final void Function(int index)? onRemovePendingItemAssign;

  /// When set, only these who-crops (item-level or one key period).
  final List<Tag>? cropTags;

  /// Included exclusions belong on the item-level grid, not a period tile.
  final bool includeIncludedExclusions;

  /// Whole-item assign when there are no face crops.
  final bool allowItemAssign;

  final Key faceGridKey;
  final Key faceHintKey;

  @override
  State<KnowledgeView> createState() => _KnowledgeViewState();
}

class _KnowledgeViewState extends State<KnowledgeView> {
  String? _selected;
  final FaceCropTapTracker _faceTapTracker = FaceCropTapTracker();

  void _toggle(String id) {
    setState(() => _selected = _selected == id ? null : id);
  }

  String? _cropPersonId(Tag tag) {
    final appearance = appearanceForWhoTag(widget.knowledge, tag.id);
    return effectiveAssignedPerson(
      intent: widget.cropIntents[tag.id],
      baselinePersonId: appearance?.personId,
      personNamesById: widget.personNamesById,
    ).personId;
  }

  String? _includedPersonId(WhoExclusion exclusion) {
    return effectiveAssignedPerson(
      intent: widget.exclusionIntents[exclusion.id],
      baselinePersonId: null,
      personNamesById: widget.personNamesById,
    ).personId;
  }

  void _onFaceTileTap(String sel, String? personId) {
    if (_faceTapTracker.registerTap(sel)) {
      if (personId != null) widget.onPersonTap?.call(personId);
      return;
    }
    _toggle(sel);
  }

  String _cropCaption(Tag tag) {
    final appearance = appearanceForWhoTag(widget.knowledge, tag.id);
    final effective = effectiveAssignedPerson(
      intent: widget.cropIntents[tag.id],
      baselinePersonId: appearance?.personId,
      personNamesById: widget.personNamesById,
    );
    final personName = effective.personName;
    if (personName != null && personName.isNotEmpty) return personName;
    final whoLabel = tag.value.trim();
    return whoLabel.isNotEmpty ? whoLabel : 'Unassigned';
  }

  String _includedCaption(WhoExclusion exclusion) {
    final effective = effectiveAssignedPerson(
      intent: widget.exclusionIntents[exclusion.id],
      baselinePersonId: null,
      personNamesById: widget.personNamesById,
    );
    final personName = effective.personName;
    if (personName != null && personName.isNotEmpty) return personName;
    return 'Unassigned';
  }

  Future<void> _excludeCrop(String tagId) async {
    await widget.onExcludeCrop!(tagId);
    if (!mounted) return;
    if (_selected == 'crop:$tagId') setState(() => _selected = null);
  }

  Future<void> _excludeIncluded(String exclusionId) async {
    await widget.onExcludeIncludedExclusion!(exclusionId);
    if (!mounted) return;
    if (_selected == 'included:$exclusionId') {
      setState(() => _selected = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final knowledge = widget.knowledge;
    final crops = widget.cropTags ?? whoFaceCropTags(knowledge);
    final itemAssignments = itemLevelPersonAssignments(knowledge);
    final included = [
      if (widget.includeIncludedExclusions)
        for (final exclusion in knowledge.whoExclusions)
          if (widget.exclusionIntents[exclusion.id]?.include == true) exclusion,
    ];
    final draftPersonNames = uniqueDraftPersonNames(
      persons: widget.persons,
      names: [
        for (final intent in widget.cropIntents.values) intent.name,
        for (final intent in widget.appearanceIntents.values) intent.name,
        for (final intent in widget.exclusionIntents.values) intent.name,
        for (final intent in widget.pendingItemAssigns) intent.name,
      ],
    );
    final visibleCrops = [
      for (final tag in crops)
        if (widget.cropIntents[tag.id]?.exclude != true) tag,
    ];
    if (visibleCrops.isNotEmpty || included.isNotEmpty) {
      return _faceGrid(
        visibleCrops: visibleCrops,
        included: included,
        draftPersonNames: draftPersonNames,
      );
    }

    final cells = <Widget>[];
    for (final appearance in itemAssignments) {
      cells.add(
        _ItemAssignRow(
          appearance: appearance,
          personNamesById: widget.personNamesById,
          persons: widget.persons,
          draftPersonNames: draftPersonNames,
          intent: widget.appearanceIntents[appearance.id],
          enabled: widget.assignEnabled,
          onPersonTap: widget.onPersonTap,
          onReassignAppearance: widget.onReassignAppearance,
          onUnassign: widget.onUnassign,
        ),
      );
    }
    for (var i = 0; i < widget.pendingItemAssigns.length; i++) {
      final intent = widget.pendingItemAssigns[i];
      cells.add(
        _PendingItemAssignRow(
          index: i,
          intent: intent,
          enabled: widget.assignEnabled,
          onRemove: widget.onRemovePendingItemAssign,
        ),
      );
    }
    if (widget.allowItemAssign && widget.onAssignItem != null) {
      cells.add(
        PersonAssignControl(
          key: const Key('item-assign-person'),
          persons: widget.persons,
          draftPersonNames: draftPersonNames,
          enabled: widget.assignEnabled,
          label: itemAssignments.isEmpty && widget.pendingItemAssigns.isEmpty
              ? 'Assign to person'
              : 'Assign another person',
          onAssign: ({personId, name}) =>
              widget.onAssignItem!(personId: personId, name: name),
        ),
      );
    }
    if (cells.isEmpty) return const SizedBox.shrink();
    return _ItemAssignList(cells: cells);
  }

  Widget _faceGrid({
    required List<Tag> visibleCrops,
    required List<WhoExclusion> included,
    required List<String> draftPersonNames,
  }) {
    final knowledge = widget.knowledge;
    final entries = <({String sel, String caption, Widget tile})>[
      for (final tag in visibleCrops)
        (
          sel: 'crop:${tag.id}',
          caption: _cropCaption(tag),
          tile: _FaceTile(
            tileKey: Key('item-face-tile-${tag.id}'),
            selectedKey: Key('item-face-selected-${tag.id}'),
            selected: _selected == 'crop:${tag.id}',
            onTap: () => _onFaceTileTap('crop:${tag.id}', _cropPersonId(tag)),
            thumb: WhoFaceCropThumb(
              itemId: appearanceForWhoTag(knowledge, tag.id)?.itemId ??
                  widget.itemId ??
                  knowledge.item.id,
              tagId: tag.id,
              knowledge: knowledge,
              size: _kFaceThumbSize,
            ),
            caption: _cropCaption(tag),
            captionKey: Key('appearance-crop-${tag.id}'),
          ),
        ),
      for (final exclusion in included)
        (
          sel: 'included:${exclusion.id}',
          caption: _includedCaption(exclusion),
          tile: _FaceTile(
            tileKey: Key('item-face-tile-included-${exclusion.id}'),
            selectedKey: Key('item-face-selected-included-${exclusion.id}'),
            selected: _selected == 'included:${exclusion.id}',
            onTap: () => _onFaceTileTap(
              'included:${exclusion.id}',
              _includedPersonId(exclusion),
            ),
            thumb: WhoExclusionCropThumb(
              key: Key('who-exclusion-included-${exclusion.id}'),
              itemId: exclusion.itemId,
              region: exclusion.region,
              item: knowledge.item,
              size: _kFaceThumbSize,
            ),
            caption: _includedCaption(exclusion),
            captionKey: Key('appearance-included-${exclusion.id}'),
          ),
        ),
    ];
    final ordered = sortedAlphaBy(entries, (e) => e.caption);
    final selected = _selected;
    final selectedVisible =
        selected != null && ordered.any((e) => e.sel == selected);
    Tag? selectedTag;
    WhoExclusion? selectedIncluded;
    if (selectedVisible && selected.startsWith('crop:')) {
      final id = selected.substring(5);
      for (final tag in visibleCrops) {
        if (tag.id == id) {
          selectedTag = tag;
          break;
        }
      }
    } else if (selectedVisible && selected.startsWith('included:')) {
      final id = selected.substring(9);
      for (final exclusion in included) {
        if (exclusion.id == id) {
          selectedIncluded = exclusion;
          break;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          key: widget.faceGridKey,
          spacing: 8,
          runSpacing: 8,
          children: [for (final e in ordered) e.tile],
        ),
        const SizedBox(height: 16),
        if (!selectedVisible)
          Text(
            'Tap a face to see its actions.',
            key: widget.faceHintKey,
            style: Theme.of(context).textTheme.bodySmall,
          )
        else if (selectedTag != null)
          _CropActions(
            tag: selectedTag,
            knowledge: knowledge,
            persons: widget.persons,
            personNamesById: widget.personNamesById,
            draftPersonNames: draftPersonNames,
            intent: widget.cropIntents[selectedTag.id],
            enabled: widget.assignEnabled,
            onPersonTap: widget.onPersonTap,
            onAssignCrop: widget.onAssignCrop,
            onUnassign: widget.onUnassign,
            onExcludeCrop: widget.onExcludeCrop == null ? null : _excludeCrop,
          )
        else if (selectedIncluded != null)
          _IncludedActions(
            exclusion: selectedIncluded,
            persons: widget.persons,
            personNamesById: widget.personNamesById,
            draftPersonNames: draftPersonNames,
            intent: widget.exclusionIntents[selectedIncluded.id],
            enabled: widget.assignEnabled,
            onPersonTap: widget.onPersonTap,
            onAssign: widget.onAssignIncludedExclusion,
            onExclude: widget.onExcludeIncludedExclusion == null
                ? null
                : _excludeIncluded,
          ),
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
    this.includedExclusionIds = const {},
    this.onIncludeExclusion,
    this.onIncludeDraftCrop,
    this.includeEnabled = true,
  });

  final ItemKnowledge knowledge;
  final List<Tag> draftExcludedCrops;
  final Set<String> includedExclusionIds;
  final Future<void> Function(String exclusionId)? onIncludeExclusion;
  final Future<void> Function(String tagId)? onIncludeDraftCrop;
  final bool includeEnabled;

  @override
  Widget build(BuildContext context) {
    final saved = [
      for (final exclusion in knowledge.whoExclusions)
        if (!includedExclusionIds.contains(exclusion.id)) exclusion,
    ];
    if (saved.isEmpty && draftExcludedCrops.isEmpty) {
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
            for (final exclusion in saved)
              _ExcludedFaceCell(
                thumb: WhoExclusionCropThumb(
                  key: Key('who-exclusion-${exclusion.id}'),
                  itemId: exclusion.itemId,
                  region: exclusion.region,
                  item: knowledge.item,
                  size: _kFaceThumbSize,
                ),
                includeKey: Key('item-include-exclusion-${exclusion.id}'),
                onInclude: onIncludeExclusion == null
                    ? null
                    : () => onIncludeExclusion!(exclusion.id),
                enabled: includeEnabled,
              ),
            for (final tag in draftExcludedCrops)
              if (tag.region != null)
                _ExcludedFaceCell(
                  thumb: WhoExclusionCropThumb(
                    key: Key('who-exclusion-draft-${tag.id}'),
                    itemId: knowledge.item.id,
                    region: tag.region!,
                    item: knowledge.item,
                    size: _kFaceThumbSize,
                  ),
                  includeKey: Key('item-include-face-${tag.id}'),
                  onInclude: onIncludeDraftCrop == null
                      ? null
                      : () => onIncludeDraftCrop!(tag.id),
                  enabled: includeEnabled,
                ),
          ],
        ),
      ],
    );
  }
}

class _ExcludedFaceCell extends StatelessWidget {
  const _ExcludedFaceCell({
    required this.thumb,
    required this.includeKey,
    this.onInclude,
    required this.enabled,
  });

  final Widget thumb;
  final Key includeKey;
  final VoidCallback? onInclude;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        thumb,
        if (onInclude != null)
          TextButton(
            key: includeKey,
            onPressed: enabled ? onInclude : null,
            child: const Text('Include'),
          ),
      ],
    );
  }
}

class _FaceTile extends StatelessWidget {
  const _FaceTile({
    required this.tileKey,
    required this.selectedKey,
    required this.selected,
    required this.onTap,
    required this.thumb,
    required this.caption,
    required this.captionKey,
  });

  final Key tileKey;
  final Key selectedKey;
  final bool selected;
  final VoidCallback onTap;
  final Widget thumb;
  final String caption;
  final Key captionKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: _kFaceCellWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: tileKey,
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: DecoratedBox(
            key: selected ? selectedKey : null,
            decoration: BoxDecoration(
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  thumb,
                  const SizedBox(height: 6),
                  Text(
                    caption,
                    key: captionKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CropActions extends StatelessWidget {
  const _CropActions({
    required this.tag,
    required this.knowledge,
    required this.persons,
    required this.personNamesById,
    this.draftPersonNames = const [],
    this.intent,
    required this.enabled,
    this.onPersonTap,
    this.onAssignCrop,
    this.onUnassign,
    this.onExcludeCrop,
  });

  final Tag tag;
  final ItemKnowledge knowledge;
  final List<Person> persons;
  final Map<String, String> personNamesById;
  final List<String> draftPersonNames;
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
    final effective = effectiveAssignedPerson(
      intent: intent,
      baselinePersonId: appearance?.personId,
      personNamesById: personNamesById,
    );
    final personId = effective.personId;
    final personName = effective.personName;
    final named = personName != null && personName.isNotEmpty;
    final canOpenPerson = personId != null && onPersonTap != null;
    final canUnassign = appearance?.id != null &&
        personId != null &&
        onUnassign != null &&
        !effective.unassign;
    return Column(
      key: const Key('item-face-actions'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onAssignCrop != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: PersonAssignControl(
              key: Key('item-assign-face-${tag.id}'),
              persons: persons,
              currentPersonId: personId,
              currentPersonName: personName,
              draftPersonNames: draftPersonNames,
              enabled: enabled,
              label: named ? 'Reassign' : 'Assign',
              onAssign: ({personId, name}) => onAssignCrop!(
                tag.id,
                personId: personId,
                name: name,
              ),
            ),
          ),
        if (canOpenPerson || canUnassign || onExcludeCrop != null)
          Wrap(
            spacing: 8,
            children: [
              if (canOpenPerson)
                OutlinedButton(
                  key: Key('item-face-open-person-${tag.id}'),
                  onPressed:
                      enabled ? () => onPersonTap!(personId) : null,
                  child: const Text('Open person'),
                ),
              if (canUnassign)
                TextButton(
                  key: Key('item-unassign-${appearance!.id}'),
                  onPressed:
                      enabled ? () => onUnassign!(appearance.id) : null,
                  child: const Text('Unassign'),
                ),
              if (onExcludeCrop != null)
                TextButton(
                  key: Key('item-exclude-face-${tag.id}'),
                  onPressed: enabled ? () => onExcludeCrop!(tag.id) : null,
                  child: const Text('Exclude from photo'),
                ),
            ],
          ),
      ],
    );
  }
}

class _ItemAssignList extends StatelessWidget {
  const _ItemAssignList({required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
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
}

class _ItemAssignRow extends StatelessWidget {
  const _ItemAssignRow({
    required this.appearance,
    required this.personNamesById,
    required this.persons,
    this.draftPersonNames = const [],
    this.intent,
    required this.enabled,
    this.onPersonTap,
    this.onReassignAppearance,
    this.onUnassign,
  });

  final PersonAppearance appearance;
  final Map<String, String> personNamesById;
  final List<Person> persons;
  final List<String> draftPersonNames;
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
    final effective = effectiveAssignedPerson(
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
                currentPersonName: effective.personName,
                draftPersonNames: draftPersonNames,
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

class _IncludedActions extends StatelessWidget {
  const _IncludedActions({
    required this.exclusion,
    required this.persons,
    required this.personNamesById,
    this.draftPersonNames = const [],
    this.intent,
    required this.enabled,
    this.onPersonTap,
    this.onAssign,
    this.onExclude,
  });

  final WhoExclusion exclusion;
  final List<Person> persons;
  final Map<String, String> personNamesById;
  final List<String> draftPersonNames;
  final PersonAssignIntent? intent;
  final bool enabled;
  final void Function(String personId)? onPersonTap;
  final Future<void> Function(
    String exclusionId, {
    String? personId,
    String? name,
  })? onAssign;
  final Future<void> Function(String exclusionId)? onExclude;

  @override
  Widget build(BuildContext context) {
    final effective = effectiveAssignedPerson(
      intent: intent,
      baselinePersonId: null,
      personNamesById: personNamesById,
    );
    final personId = effective.personId;
    final personName = effective.personName;
    final named = personName != null && personName.isNotEmpty;
    final canOpenPerson = personId != null && onPersonTap != null;
    return Column(
      key: const Key('item-face-actions'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onAssign != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: PersonAssignControl(
              key: Key('item-assign-included-${exclusion.id}'),
              persons: persons,
              currentPersonId: personId,
              currentPersonName: personName,
              draftPersonNames: draftPersonNames,
              enabled: enabled,
              label: named ? 'Reassign' : 'Assign',
              onAssign: ({personId, name}) => onAssign!(
                exclusion.id,
                personId: personId,
                name: name,
              ),
            ),
          ),
        if (canOpenPerson || onExclude != null)
          Wrap(
            spacing: 8,
            children: [
              if (canOpenPerson)
                OutlinedButton(
                  key: Key('item-face-open-person-included-${exclusion.id}'),
                  onPressed:
                      enabled ? () => onPersonTap!(personId) : null,
                  child: const Text('Open person'),
                ),
              if (onExclude != null)
                TextButton(
                  key: Key('item-exclude-included-${exclusion.id}'),
                  onPressed: enabled ? () => onExclude!(exclusion.id) : null,
                  child: const Text('Exclude from photo'),
                ),
            ],
          ),
      ],
    );
  }
}
