import 'dart:math' as math;

import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_edits.dart';
import 'package:tagkin_desktop/persons/person_name.dart';
import 'package:tagkin_desktop/ui/alpha_order.dart';

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

/// Active tags for Folders / item-detail CSV: item-level plus unique
/// key-period values (videos would otherwise look empty).
Map<String, List<Tag>> groupDisplayTagsByDimension(ItemKnowledge knowledge) {
  final grouped = groupItemLevelTagsByDimension(knowledge.tags);
  final seen = {
    for (final d in kKnowledgeDimensions)
      d: {for (final t in grouped[d]!) t.value.toLowerCase()},
  };
  void add(Tag tag) {
    if (tag.status != TagStatus.active) return;
    final bucket = grouped[tag.dimension];
    final keys = seen[tag.dimension];
    if (bucket == null || keys == null) return;
    final key = tag.value.toLowerCase();
    if (!keys.add(key)) return;
    bucket.add(tag);
  }

  for (final period in knowledge.keyPeriods) {
    for (final tag in period.tags) {
      add(tag);
    }
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
/// `personId` present in [namesById], sorted A–Z case-insensitive.
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
  return sortedAlphaBy(out, (n) => n);
}

/// Folder-table Who: person names when any assigned appearance resolves;
/// otherwise active item-level who-tag values. Both lists are A–Z
/// (case-insensitive).
List<String> whoColumnValues(
  ItemKnowledge knowledge,
  Map<String, String> namesById,
) {
  final names = assignedPersonNames(knowledge, namesById);
  if (names.isNotEmpty) return names;
  return sortedAlphaBy([
    for (final tag in groupDisplayTagsByDimension(knowledge)['who']!)
      tag.value,
  ], (v) => v);
}

/// Active who tag with a face box (item-detail crop).
bool tagIsWhoFaceCrop(Tag tag) {
  return tag.dimension == 'who' &&
      tag.status == TagStatus.active &&
      tag.region != null;
}

bool itemHasWhoFaceCrops(ItemKnowledge knowledge) {
  return whoFaceCropTags(knowledge).isNotEmpty;
}

List<Tag> whoFaceCropTags(ItemKnowledge knowledge) {
  final seen = <String>{};
  final out = <Tag>[];
  void add(Tag tag) {
    if (!tagIsWhoFaceCrop(tag) || !seen.add(tag.id)) return;
    out.add(tag);
  }

  for (final tag in knowledge.tags) {
    add(tag);
  }
  for (final period in knowledge.keyPeriods) {
    for (final tag in period.tags) {
      add(tag);
    }
  }
  return out;
}

/// Who-face crops with no key period (item-level; photos, or rare video tags).
List<Tag> itemLevelWhoFaceCropTags(ItemKnowledge knowledge) {
  return [
    for (final tag in whoFaceCropTags(knowledge))
      if (tag.keyPeriodId == null) tag,
  ];
}

/// Who-face crops on one key period, in `period.tags` order.
List<Tag> whoFaceCropTagsForPeriod(
  ItemKnowledge knowledge,
  String keyPeriodId,
) {
  for (final period in knowledge.keyPeriods) {
    if (period.id != keyPeriodId) continue;
    return [
      for (final tag in period.tags)
        if (tagIsWhoFaceCrop(tag)) tag,
    ];
  }
  return const [];
}

/// Intersection-over-union of two normalized face boxes. Empty boxes → 0.
double regionIou(TagRegion a, TagRegion b) {
  final xA = math.max(a.xMin, b.xMin);
  final yA = math.max(a.yMin, b.yMin);
  final xB = math.min(a.xMax, b.xMax);
  final yB = math.min(a.yMax, b.yMax);
  final interW = math.max(0.0, xB - xA);
  final interH = math.max(0.0, yB - yA);
  final inter = interW * interH;
  final areaA = math.max(0.0, a.xMax - a.xMin) * math.max(0.0, a.yMax - a.yMin);
  final areaB = math.max(0.0, b.xMax - b.xMin) * math.max(0.0, b.yMax - b.yMin);
  final union = areaA + areaB - inter;
  if (union <= 0) return 0;
  return inter / union;
}

/// Same-still duplicate boxes on one key period (IoU ≥ 0.5). Keep first in
/// [tags] order; later overlaps are exclude candidates. Never call this across
/// periods — identical coordinates on two periods are two people.
const double kWhoFaceOverlapIouThreshold = 0.5;

({List<Tag> kept, List<String> excludeIds}) collapseOverlappingWhoFaces(
  List<Tag> tags,
) {
  final kept = <Tag>[];
  final excludeIds = <String>[];
  for (final tag in tags) {
    if (!tagIsWhoFaceCrop(tag)) continue;
    final region = tag.region!;
    final overlapsKept = kept.any(
      (k) => regionIou(k.region!, region) >= kWhoFaceOverlapIouThreshold,
    );
    if (overlapsKept) {
      excludeIds.add(tag.id);
    } else {
      kept.add(tag);
    }
  }
  return (kept: kept, excludeIds: excludeIds);
}

/// NMS exclude ids for every key period independently.
List<String> overlappingWhoFaceExcludeIds(ItemKnowledge knowledge) {
  final ids = <String>[];
  for (final period in knowledge.keyPeriods) {
    final collapsed = collapseOverlappingWhoFaces(
      whoFaceCropTagsForPeriod(knowledge, period.id),
    );
    ids.addAll(collapsed.excludeIds);
  }
  return ids;
}

/// Period text lines: skip who-with-region (those render as face thumbs).
bool tagShowsAsKeyPeriodText(Tag tag) {
  if (tag.status != TagStatus.active) return false;
  return !tagIsWhoFaceCrop(tag);
}

/// Sample-frame timestamp for a who tag on a video key period, if any.
int? sampleTimestampMsForWhoTag(ItemKnowledge knowledge, Tag tag) {
  return sampleTimestampMsForTagId(knowledge, tag.id, tag.keyPeriodId);
}

int? sampleTimestampMsForTagId(
  ItemKnowledge knowledge,
  String tagId, [
  String? keyPeriodId,
]) {
  if (keyPeriodId != null) {
    for (final period in knowledge.keyPeriods) {
      if (period.id == keyPeriodId) return period.sampleTimestampMs;
    }
  }
  for (final period in knowledge.keyPeriods) {
    if (period.tags.any((t) => t.id == tagId)) return period.sampleTimestampMs;
  }
  return null;
}

/// Who-face crop tag plus its video sample timestamp (null on photos).
({Tag tag, int? sampleTimestampMs})? findWhoFaceTag(
  ItemKnowledge knowledge,
  String tagId,
) {
  for (final tag in whoFaceCropTags(knowledge)) {
    if (tag.id != tagId) continue;
    return (
      tag: tag,
      sampleTimestampMs: sampleTimestampMsForWhoTag(knowledge, tag),
    );
  }
  return null;
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
  /// When set (video key-period crop), occupancy is that period only.
  String? sameKeyPeriodId,
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
    if (sameKeyPeriodId != null && tag.keyPeriodId != sameKeyPeriodId) {
      continue;
    }
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
    if (sameKeyPeriodId != null) continue;
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
    if (sameKeyPeriodId != null) continue;
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
