import 'package:tagkin_desktop/contract/contract.dart';

/// Which tray a face crop currently sits in (assigned / unassigned / excluded).
enum FaceCropTray { assigned, unassigned, excluded }

/// Kind of face entry for multi-select (appearances and exclusions do not mix).
enum FaceCropSelectKind { appearance, exclusion }

/// One face crop move between trays (D9).
class FaceCropDragData {
  const FaceCropDragData.appearance({
    required this.source,
    required this.appearanceId,
    required this.itemId,
    required this.tagId,
    this.personId,
    this.faceGroupId,
    this.faceGroupKind,
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
        personId = null,
        faceGroupId = null,
        faceGroupKind = null;

  final FaceCropTray source;
  final String? appearanceId;
  final String? exclusionId;
  final String itemId;
  final String? tagId;
  final String? personId;
  final String? faceGroupId;
  final FaceGroupKind? faceGroupKind;
  final String? createdFromTagId;
  final TagRegion? region;

  bool get isAppearance => appearanceId != null;
  bool get isExclusion => exclusionId != null;

  String get selectionId => appearanceId ?? exclusionId!;
}

/// Drag payload: one or more faces from the same tray.
class FaceCropDragPayload {
  const FaceCropDragPayload({
    required this.source,
    required this.items,
  });

  factory FaceCropDragPayload.single(FaceCropDragData item) =>
      FaceCropDragPayload(source: item.source, items: [item]);

  final FaceCropTray source;
  final List<FaceCropDragData> items;

  int get count => items.length;
}

/// Same-tray drops are no-ops, except Assigned → Assigned onto a *different*
/// selected person (reassign without an Unassigned hop).
bool ignoreSameTrayFaceCropDrop({
  required FaceCropTray source,
  required FaceCropTray target,
  String? dataPersonId,
  String? selectedPersonId,
}) {
  if (source != target) return false;
  if (target != FaceCropTray.assigned) return true;
  if (dataPersonId == null || dataPersonId == selectedPersonId) return true;
  return false;
}
