import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_edits.dart';
import 'package:tagkin_desktop/persons/person_name.dart';

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

/// Draft-aware assigned person for a crop or appearance row.
({String? personId, String? personName, bool unassign}) effectiveAssignedPerson({
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

/// Assigned person name per who-face-crop tag id (draft-aware).
///
/// Unassign / exclude drafts omit the tag so the face box keeps `tag.value`.
Map<String, String> whoOverlayPersonNames({
  required ItemKnowledge knowledge,
  required Map<String, PersonAssignIntent> cropIntents,
  required Map<String, String> personNamesById,
}) {
  final out = <String, String>{};
  for (final tag in whoFaceCropTags(knowledge)) {
    final intent = cropIntents[tag.id];
    if (intent?.unassign == true || intent?.exclude == true) continue;
    final person = effectiveAssignedPerson(
      intent: intent,
      baselinePersonId: appearanceForWhoTag(knowledge, tag.id)?.personId,
      personNamesById: personNamesById,
    );
    final name = person.personName?.trim();
    if (name != null && name.isNotEmpty) out[tag.id] = name;
  }
  return out;
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

/// Person ids and name-keys already taken on this item (draft-aware).
({Set<String> personIds, Set<String> nameKeys}) draftPersonKeysOnItem({
  required ItemKnowledge knowledge,
  required Map<String, PersonAssignIntent> cropIntents,
  required Map<String, PersonAssignIntent> appearanceIntents,
  required Map<String, PersonAssignIntent> exclusionIntents,
  required List<PersonAssignIntent> pendingItemAssigns,
  required Map<String, String> personNamesById,
  String? exceptTagId,
  String? exceptAppearanceId,
  String? exceptExclusionId,
}) {
  final personIds = <String>{};
  final nameKeys = <String>{};
  void add(String? id, String? name) {
    if (id != null && id.isNotEmpty) personIds.add(id);
    final n = name?.trim();
    if (n != null && n.isNotEmpty) nameKeys.add(personNameKey(n));
  }

  for (final tag in whoFaceCropTags(knowledge)) {
    if (tag.id == exceptTagId) continue;
    final intent = cropIntents[tag.id];
    if (intent?.unassign == true || intent?.exclude == true) continue;
    final person = effectiveAssignedPerson(
      intent: intent,
      baselinePersonId: appearanceForWhoTag(knowledge, tag.id)?.personId,
      personNamesById: personNamesById,
    );
    add(person.personId, person.personName);
  }
  for (final appearance in itemLevelPersonAssignments(knowledge)) {
    if (appearance.id == exceptAppearanceId) continue;
    final intent = appearanceIntents[appearance.id];
    if (intent?.unassign == true) continue;
    final person = effectiveAssignedPerson(
      intent: intent,
      baselinePersonId: appearance.personId,
      personNamesById: personNamesById,
    );
    add(person.personId, person.personName);
  }
  for (final intent in pendingItemAssigns) {
    if (!intent.hasTarget) continue;
    add(
      intent.personId,
      intent.name ??
          (intent.personId != null ? personNamesById[intent.personId] : null),
    );
  }
  for (final exclusion in knowledge.whoExclusions) {
    if (exclusion.id == exceptExclusionId) continue;
    final intent = exclusionIntents[exclusion.id];
    if (intent == null || !intent.include || !intent.hasTarget) continue;
    add(
      intent.personId,
      intent.name ??
          (intent.personId != null ? personNamesById[intent.personId] : null),
    );
  }
  return (personIds: personIds, nameKeys: nameKeys);
}

bool personOccupiedOnItem({
  required ({Set<String> personIds, Set<String> nameKeys}) occupied,
  String? personId,
  String? name,
  Map<String, String> personNamesById = const {},
}) {
  if (personId != null &&
      personId.isNotEmpty &&
      occupied.personIds.contains(personId)) {
    return true;
  }
  final resolved = name?.trim().isNotEmpty == true
      ? name!.trim()
      : (personId != null ? personNamesById[personId]?.trim() : null);
  if (resolved == null || resolved.isEmpty) return false;
  return occupied.nameKeys.contains(personNameKey(resolved));
}
