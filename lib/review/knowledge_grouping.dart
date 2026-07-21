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
