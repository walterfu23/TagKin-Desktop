import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/where/where_value_text.dart';

/// Renders approved who/what/when/where from [ItemKnowledge] (D8 + D10).
///
/// Canonical terms only (R2). Optional correction callbacks enable add/edit/
/// remove (D10). Person appearance rows link to D9 when [onPersonTap] is set.
class KnowledgeView extends StatelessWidget {
  const KnowledgeView({
    super.key,
    required this.knowledge,
    this.itemId,
    this.onPersonTap,
    this.onAddTag,
    this.onEditTag,
    this.onRemoveTag,
    this.onExcludeWho,
    this.onUndoWhoExclusion,
    this.correctionsEnabled = true,
  });

  final ItemKnowledge knowledge;

  /// Host item id — enables who-face crop thumbs on appearance rows.
  final String? itemId;

  /// Opens person detail for a linked appearance (D9).
  final void Function(String personId)? onPersonTap;

  /// Add a tag for [dimension] (D10).
  final void Function(String dimension)? onAddTag;

  /// Edit an existing tag (D10).
  final void Function(Tag tag)? onEditTag;

  /// Remove an existing tag (D10).
  final void Function(Tag tag)? onRemoveTag;

  /// Durable exclude who face from this photo (survives re-analyze).
  final void Function(Tag tag)? onExcludeWho;

  /// Undo a who-face exclusion (R6).
  final void Function(WhoExclusion exclusion)? onUndoWhoExclusion;

  final bool correctionsEnabled;

  bool get _canCorrect =>
      correctionsEnabled &&
      (onAddTag != null ||
          onEditTag != null ||
          onRemoveTag != null ||
          onExcludeWho != null);

  @override
  Widget build(BuildContext context) {
    final grouped = groupItemLevelTagsByDimension(knowledge.tags);
    final hasAny = grouped.values.any((list) => list.isNotEmpty);

    return Column(
      key: const Key('knowledge-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Knowledge',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (!hasAny && !_canCorrect)
          const Text(
            'No tags yet — run Analyze when ready.',
            key: Key('knowledge-empty'),
          )
        else
          for (final dimension in kKnowledgeDimensions)
            _DimensionSection(
              dimension: dimension,
              tags: grouped[dimension]!,
              onAddTag: onAddTag,
              onEditTag: onEditTag,
              onRemoveTag: onRemoveTag,
              onExcludeWho: dimension == 'who' ? onExcludeWho : null,
              enabled: correctionsEnabled,
            ),
        if (knowledge.whoExclusions.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Excluded faces',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final exclusion in knowledge.whoExclusions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                key: Key('who-exclusion-${exclusion.id}'),
                children: [
                  Expanded(
                    child: Text(
                      'Excluded face (${exclusion.id.substring(0, 8)}…)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (onUndoWhoExclusion != null && correctionsEnabled)
                    TextButton(
                      key: Key('who-exclusion-undo-${exclusion.id}'),
                      onPressed: () => onUndoWhoExclusion!(exclusion),
                      child: const Text('Undo'),
                    ),
                ],
              ),
            ),
        ],
        if (knowledge.appearances.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Person appearances',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final appearance in knowledge.appearances)
            _AppearanceRow(
              appearance: appearance,
              knowledge: knowledge,
              itemId: itemId,
              onPersonTap: onPersonTap,
            ),
        ],
      ],
    );
  }
}

class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({
    required this.appearance,
    required this.knowledge,
    this.itemId,
    this.onPersonTap,
  });

  final PersonAppearance appearance;
  final ItemKnowledge knowledge;
  final String? itemId;
  final void Function(String personId)? onPersonTap;

  @override
  Widget build(BuildContext context) {
    final personId = appearance.personId;
    Tag? whoTag;
    if (appearance.tagId != null) {
      for (final t in knowledge.tags) {
        if (t.id == appearance.tagId) {
          whoTag = t;
          break;
        }
      }
    }
    final whoLabel =
        (whoTag != null && whoTag.value.trim().isNotEmpty)
            ? whoTag.value.trim()
            : null;
    final label = [
      ?whoLabel,
      'appearance ${appearance.id}',
      if (personId != null) '→ person $personId',
    ].join(' ');
    final text = Text(
      label,
      key: Key('appearance-${appearance.id}'),
    );
    final cropItemId = appearance.itemId ?? itemId;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (cropItemId != null && appearance.tagId != null) ...[
          WhoFaceCropThumb(
            itemId: cropItemId,
            tagId: appearance.tagId!,
            knowledge: knowledge,
            size: 40,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: text),
      ],
    );
    if (personId != null && onPersonTap != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: InkWell(
          key: Key('appearance-person-link-${appearance.id}'),
          onTap: () => onPersonTap!(personId),
          child: row,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: row,
    );
  }
}

class _DimensionSection extends StatelessWidget {
  const _DimensionSection({
    required this.dimension,
    required this.tags,
    this.onAddTag,
    this.onEditTag,
    this.onRemoveTag,
    this.onExcludeWho,
    this.enabled = true,
  });

  final String dimension;
  final List<Tag> tags;
  final void Function(String dimension)? onAddTag;
  final void Function(Tag tag)? onEditTag;
  final void Function(Tag tag)? onRemoveTag;
  final void Function(Tag tag)? onExcludeWho;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dimension,
                  key: Key('knowledge-dimension-$dimension'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              if (onAddTag != null)
                IconButton(
                  key: Key('tag-add-$dimension'),
                  tooltip: 'Add tag',
                  iconSize: 18,
                  onPressed: enabled ? () => onAddTag!(dimension) : null,
                  icon: const Icon(Icons.add),
                ),
            ],
          ),
          if (tags.isEmpty)
            const Text('—')
          else
            for (final tag in tags)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: dimension == 'where'
                          ? WhereValueText(
                              key: Key('tag-value-${tag.id}'),
                              value: tag.value,
                            )
                          : Text(
                              tag.value,
                              key: Key('tag-value-${tag.id}'),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        provenanceLabel(tag),
                        key: Key('tag-provenance-${tag.id}'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                        textAlign: TextAlign.end,
                      ),
                    ),
                    if (onEditTag != null)
                      IconButton(
                        key: Key('tag-edit-${tag.id}'),
                        tooltip: 'Edit tag',
                        iconSize: 18,
                        onPressed: enabled ? () => onEditTag!(tag) : null,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    if (onRemoveTag != null)
                      IconButton(
                        key: Key('tag-remove-${tag.id}'),
                        tooltip: 'Remove tag',
                        iconSize: 18,
                        onPressed: enabled ? () => onRemoveTag!(tag) : null,
                        icon: const Icon(Icons.close),
                      ),
                    if (onExcludeWho != null && tag.region != null)
                      IconButton(
                        key: Key('tag-exclude-${tag.id}'),
                        tooltip: 'Exclude from this photo',
                        iconSize: 18,
                        onPressed: enabled ? () => onExcludeWho!(tag) : null,
                        icon: const Icon(Icons.person_off_outlined),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
