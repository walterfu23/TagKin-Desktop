import 'package:tagkin_desktop/contract/contract.dart';

/// Canonical who/what/when/where dimensions (R2).
const List<String> kKnowledgeDimensions = <String>[
  'who',
  'what',
  'when',
  'where',
];

/// Groups active item-level tags by dimension for the review overlay.
///
/// Tags attached to a [keyPeriodId] are excluded — those render under the
/// key-period scrubber. Unknown dimensions are omitted (browse/search stays
/// out of D8 scope).
Map<String, List<Tag>> groupItemLevelTagsByDimension(List<Tag> tags) {
  final grouped = <String, List<Tag>>{
    for (final d in kKnowledgeDimensions) d: <Tag>[],
  };
  for (final tag in tags) {
    if (tag.keyPeriodId != null) continue;
    if (tag.status != TagStatus.active) continue;
    final bucket = grouped[tag.dimension];
    if (bucket != null) bucket.add(tag);
  }
  return grouped;
}

/// Human-readable label for a provenance chip (source / provider / model / confidence).
String provenanceLabel(Tag tag) {
  final parts = <String>[tag.source.wire];
  if (tag.provider != null && tag.provider!.isNotEmpty) {
    parts.add(tag.provider!);
  }
  if (tag.modelId != null && tag.modelId!.isNotEmpty) {
    parts.add(tag.modelId!);
  }
  if (tag.confidence != null) {
    parts.add('${(tag.confidence! * 100).round()}%');
  }
  return parts.join(' · ');
}

/// Unique [Person.name]s for appearances on [knowledge] that have a
/// `personId` present in [namesById], in first-seen order.
List<String> assignedPersonNames(
  ItemKnowledge knowledge,
  Map<String, String> namesById,
) {
  final seen = <String>{};
  final out = <String>[];
  for (final appearance in knowledge.appearances) {
    final id = appearance.personId;
    if (id == null || id.isEmpty) continue;
    if (!seen.add(id)) continue;
    final name = namesById[id]?.trim();
    if (name == null || name.isEmpty) continue;
    out.add(name);
  }
  return out;
}

/// Folder-table Who: person names when any assigned appearance resolves;
/// otherwise active item-level who-tag values.
List<String> whoColumnValues(
  ItemKnowledge knowledge,
  Map<String, String> namesById,
) {
  final names = assignedPersonNames(knowledge, namesById);
  if (names.isNotEmpty) return names;
  return [
    for (final tag in groupItemLevelTagsByDimension(knowledge.tags)['who']!)
      tag.value,
  ];
}

/// Active who tag with a face box (item-detail crop).
bool tagIsWhoFaceCrop(Tag tag) {
  return tag.dimension == 'who' &&
      tag.status == TagStatus.active &&
      tag.region != null;
}

bool itemHasWhoFaceCrops(ItemKnowledge knowledge) {
  return knowledge.tags.any(tagIsWhoFaceCrop);
}

List<Tag> whoFaceCropTags(ItemKnowledge knowledge) {
  return [
    for (final tag in knowledge.tags)
      if (tagIsWhoFaceCrop(tag)) tag,
  ];
}

PersonAppearance? appearanceForWhoTag(
  ItemKnowledge knowledge,
  String tagId,
) {
  for (final appearance in knowledge.appearances) {
    if (appearance.tagId == tagId) return appearance;
  }
  return null;
}

/// Whole-item person links (no face crop / no who tagId).
List<PersonAppearance> itemLevelPersonAssignments(ItemKnowledge knowledge) {
  return [
    for (final appearance in knowledge.appearances)
      if (appearance.tagId == null &&
          appearance.personId != null &&
          appearance.personId!.isNotEmpty)
        appearance,
  ];
}

/// Photo-detail Knowledge CSV: Who is names then who-tag values; other
/// dimensions are tag values only.
List<String> knowledgeCsvValues({
  required String dimension,
  required List<Tag> tags,
  List<String> personNames = const [],
}) {
  if (dimension == 'who') {
    return [...personNames, for (final tag in tags) tag.value];
  }
  return [for (final tag in tags) tag.value];
}
