import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

void main() {
  test('end fade is off unless requested', () {
    final timeline = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg')},
    );
    expect(timeline.endFade, isNull);
    expect(timeline.duration, 75);
  });

  test('end fade starts at the last clip and adds 3 seconds', () {
    final none = itemListNleTimeline(
      entries: [
        fixtureEntry(itemId: 'p1'),
        fixtureEntry(itemId: 'p2'),
      ],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg'),
        'p2': fixtureItem(id: 'p2', sourceRef: 'file:///b.jpg'),
      },
      transition: ExportPhotoTransition.none,
      endFadeSeconds: kItemListNleEndFadeSeconds,
    );
    expect(none.clips.last.timelineEnd, 150);
    expect(none.endFade!.startFrame, 150);
    expect(none.endFade!.durationFrames, 90);
    expect(none.duration, 240);
    expect(itemListNleTimelineDurationMs(none), 8000);

    final dissolve = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg')},
      transition: ExportPhotoTransition.none,
      endFadeSeconds: kItemListNleEndFadeSeconds,
    );
    expect(dissolve.transitions, isEmpty);
    expect(dissolve.endFade!.startFrame, dissolve.clips.single.timelineEnd);
  });
}
