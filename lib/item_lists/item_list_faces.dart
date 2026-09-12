import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/photo_blur_score_cache.dart';
import 'package:tagkin_desktop/prepass/sharpness.dart';

export 'package:tagkin_desktop/prepass/photo_blur_score_cache.dart'
    show isHiddenBlurryPhoto;
export 'package:tagkin_desktop/prepass/sharpness.dart'
    show kBlurrySharpnessThreshold;

/// Face boxes for the currently selected Who chips on one export row.
///
/// Matches assigned [Person.name] (case-insensitive). Key-period rows only
/// include appearances on that period. Unassigned / unnamed faces are skipped.
List<({String id, TagRegion region})> selectedWhoFaceRegions({
  required ItemListEntry entry,
  required ItemKnowledge knowledge,
  required Set<String> selectedWho,
  required Map<String, String> personNameById,
}) {
  if (selectedWho.isEmpty) return const [];
  final wanted = {for (final name in selectedWho) name.toLowerCase()};
  final out = <({String id, TagRegion region})>[];
  for (final appearance in knowledge.appearances) {
    final region = appearance.region;
    if (region == null) continue;
    if (entry.kind == ItemListEntryKind.keyperiod) {
      if (appearance.keyPeriodId != entry.keyPeriodId) continue;
    } else if (appearance.keyPeriodId != null) {
      continue;
    }
    final personId = appearance.personId;
    if (personId == null) continue;
    final name = personNameById[personId];
    if (name == null || !wanted.contains(name.toLowerCase())) continue;
    out.add((id: appearance.id, region: region));
  }
  return out;
}

/// True when this preview photo should hide on the Hide blurry toggle.
///
/// Photos only. Stored pre-pass sharpness vs the bar. Null/unknown stays
/// visible. Key periods are never hidden this way.
bool isBlurryItemListEntry({
  required ItemListEntry entry,
  required Item? item,
  double threshold = kBlurrySharpnessThreshold,
}) {
  if (entry.kind != ItemListEntryKind.photo) return false;
  if (item == null) return false;
  return isHiddenBlurryPhoto(item: item, threshold: threshold);
}
