import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_filter.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

void main() {
  test('itemListMp4XfadeName maps photo transitions', () {
    expect(itemListMp4XfadeName(ExportPhotoTransition.none), '');
    expect(itemListMp4XfadeName(ExportPhotoTransition.crossDissolve), 'fade');
    expect(itemListMp4XfadeName(ExportPhotoTransition.dipToBlack), 'fadeblack');
    expect(itemListMp4XfadeName(ExportPhotoTransition.dipToWhite), 'fadewhite');
  });

  test('itemListMp4Plan builds xfade + audio fade from the NLE timeline', () {
    final timeline = itemListNleTimeline(
      entries: [
        fixtureEntry(itemId: 'p1'),
        fixtureEntry(itemId: 'p2'),
      ],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg'),
        'p2': fixtureItem(id: 'p2', sourceRef: 'file:///b.jpg'),
      },
    );
    final plan = itemListMp4Plan(
      timeline: timeline,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    expect(plan.inputs, hasLength(2));
    expect(plan.hasXfade, isTrue);
    expect(plan.filterComplex, contains('xfade=transition=fade'));
    expect(plan.filterComplex, contains('[aout]'));
    expect(plan.filterComplex, contains('[vout]'));
    expect(plan.videoDurationSeconds, greaterThan(0));
    expect(
      itemListNleTimelineDurationMs(timeline),
      (timeline.duration * 1000 / kItemListNleTimebase).round(),
    );
  });

  test('MP4 format is a local media export, not a vendor name', () {
    expect(ItemListExportFormat.mp4WithMusic.label, 'MP4 (with music)');
    expect(ItemListExportFormat.mp4WithMusic.fileExtension, 'mp4');
  });
}
