import 'package:tagkin_desktop/contract/contract.dart';

/// Which tray a face crop currently sits in (assigned / unassigned / excluded).
enum FaceCropTray { assigned, unassigned, excluded }

/// Drag payload for moving a face crop between trays (D9 Phase 2).
class FaceCropDragData {
  const FaceCropDragData.appearance({
    required this.source,
    required this.appearanceId,
    required this.itemId,
    required this.tagId,
    this.personId,
    this.region,
  })  : exclusionId = null,
        createdFromTagId = null;

  const FaceCropDragData.exclusion({
    required this.source,
    required this.exclusionId,
    required this.itemId,
    required this.region,
    this.createdFromTagId,
  })  : appearanceId = null,
        tagId = createdFromTagId,
        personId = null;

  final FaceCropTray source;
  final String? appearanceId;
  final String? exclusionId;
  final String itemId;
  final String? tagId;
  final String? personId;
  final String? createdFromTagId;
  final TagRegion? region;

  bool get isAppearance => appearanceId != null;
  bool get isExclusion => exclusionId != null;
}
