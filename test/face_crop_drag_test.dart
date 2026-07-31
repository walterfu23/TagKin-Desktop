import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/face_crop_drag.dart';

void main() {
  group('ignoreSameTrayFaceCropDrop', () {
    test('cross-tray drops are never ignored', () {
      expect(
        ignoreSameTrayFaceCropDrop(
          source: FaceCropTray.unassigned,
          target: FaceCropTray.assigned,
          dataPersonId: null,
          selectedPersonId: 'p1',
        ),
        isFalse,
      );
    });

    test('same Unassigned or Excluded tray is ignored', () {
      expect(
        ignoreSameTrayFaceCropDrop(
          source: FaceCropTray.unassigned,
          target: FaceCropTray.unassigned,
          dataPersonId: null,
          selectedPersonId: null,
        ),
        isTrue,
      );
      expect(
        ignoreSameTrayFaceCropDrop(
          source: FaceCropTray.excluded,
          target: FaceCropTray.excluded,
          dataPersonId: null,
          selectedPersonId: null,
        ),
        isTrue,
      );
    });

    test('Assigned onto same selected person is ignored', () {
      expect(
        ignoreSameTrayFaceCropDrop(
          source: FaceCropTray.assigned,
          target: FaceCropTray.assigned,
          dataPersonId: 'p1',
          selectedPersonId: 'p1',
        ),
        isTrue,
      );
    });

    test('Assigned onto a different selected person is allowed', () {
      expect(
        ignoreSameTrayFaceCropDrop(
          source: FaceCropTray.assigned,
          target: FaceCropTray.assigned,
          dataPersonId: 'p1',
          selectedPersonId: 'p2',
        ),
        isFalse,
      );
    });
  });

  group('FaceCropDragPayload', () {
    test('single wraps one item', () {
      final item = FaceCropDragData.appearance(
        source: FaceCropTray.unassigned,
        appearanceId: 'a1',
        itemId: 'i1',
        tagId: 't1',
      );
      final payload = FaceCropDragPayload.single(item);
      expect(payload.count, 1);
      expect(payload.items.single.appearanceId, 'a1');
    });
  });
}
