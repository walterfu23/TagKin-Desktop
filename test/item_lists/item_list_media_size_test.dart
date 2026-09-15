import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/item_lists/export_sequence_size.dart';
import 'package:tagkin_desktop/item_lists/item_list_media_size.dart';

void main() {
  test('match smallest uses min width and min height', () {
    expect(
      itemListNleSequencePixelSize(
        mode: ExportSequenceSize.matchSmallest,
        probed: const [
          ItemListPixelSize(4032, 1816),
          ItemListPixelSize(1920, 1080),
        ],
      ),
      const ItemListPixelSize(1920, 1080),
    );
  });

  test('match smallest mixed aspect uses independent mins', () {
    expect(
      itemListNleSequencePixelSize(
        mode: ExportSequenceSize.matchSmallest,
        probed: const [
          ItemListPixelSize(4032, 1816),
          ItemListPixelSize(1080, 1920),
        ],
      ),
      const ItemListPixelSize(1080, 1816),
    );
  });

  test('match smallest with no probes falls back to 1080p', () {
    expect(
      itemListNleSequencePixelSize(
        mode: ExportSequenceSize.matchSmallest,
        probed: const [],
      ),
      kItemListNle1080p,
    );
  });

  test('match largest uses max width and max height', () {
    expect(
      itemListNleSequencePixelSize(
        mode: ExportSequenceSize.matchLargest,
        probed: const [
          ItemListPixelSize(4032, 1816),
          ItemListPixelSize(1920, 1080),
        ],
      ),
      const ItemListPixelSize(4032, 1816),
    );
  });

  test('match largest with no probes falls back to 1080p', () {
    expect(
      itemListNleSequencePixelSize(
        mode: ExportSequenceSize.matchLargest,
        probed: const [],
      ),
      kItemListNle1080p,
    );
  });

  test('1080p and 4K ignore probed sizes', () {
    expect(
      itemListNleSequencePixelSize(
        mode: ExportSequenceSize.p1080,
        probed: const [ItemListPixelSize(4032, 1816)],
      ),
      kItemListNle1080p,
    );
    expect(
      itemListNleSequencePixelSize(
        mode: ExportSequenceSize.p4k,
        probed: const [ItemListPixelSize(100, 100)],
      ),
      kItemListNle4k,
    );
  });

  test('scaleToFit is off only for match largest', () {
    expect(ExportSequenceSize.matchSmallest.scaleToFit, isTrue);
    expect(ExportSequenceSize.p1080.scaleToFit, isTrue);
    expect(ExportSequenceSize.p4k.scaleToFit, isTrue);
    expect(ExportSequenceSize.matchLargest.scaleToFit, isFalse);
  });

  test('parse defaults unknown wire to match smallest', () {
    expect(
      ExportSequenceSize.parse(null),
      ExportSequenceSize.matchSmallest,
    );
    expect(
      ExportSequenceSize.parse('nope'),
      ExportSequenceSize.matchSmallest,
    );
    expect(
      ExportSequenceSize.parse('matchSmallest'),
      ExportSequenceSize.matchSmallest,
    );
    expect(
      ExportSequenceSize.parse('matchLargest'),
      ExportSequenceSize.matchLargest,
    );
  });

  test('fit scale is min of both axes as percent', () {
    final percent = itemListNleFitScalePercent(
      fileWidth: 4032,
      fileHeight: 1816,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
    );
    expect(percent, closeTo(47.619, 0.001));
    expect(itemListNleNeedsFitScale(percent), isTrue);
    expect(itemListNleNeedsFitScale(100), isFalse);
  });

  test('PNG header size', () {
    final image = img.Image(width: 32, height: 16);
    final bytes = Uint8List.fromList(img.encodePng(image));
    expect(
      itemListNleStillSizeFromBytes(bytes),
      const ItemListPixelSize(32, 16),
    );
  });

  test('JPEG first SOF wins over a trailing second JPEG', () {
    final primary = img.Image(width: 48, height: 32);
    final trailing = img.Image(width: 16, height: 8);
    final bytes = Uint8List.fromList([
      ...img.encodeJpg(primary),
      ...img.encodeJpg(trailing),
    ]);
    expect(
      itemListNleJpegSofSize(bytes),
      const ItemListPixelSize(48, 32),
    );
    expect(
      itemListNleStillSizeFromBytes(bytes),
      const ItemListPixelSize(48, 32),
    );
  });

  test('JPEG SOF size of a single still', () {
    final bytes = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 64, height: 40)),
    );
    expect(
      itemListNleStillSizeFromBytes(bytes),
      const ItemListPixelSize(64, 40),
    );
  });

  test('ffprobe csv parses rotation swap', () {
    expect(
      itemListNleVideoSizeFromFfprobe('1920,1080'),
      const ItemListPixelSize(1920, 1080),
    );
    expect(
      itemListNleVideoSizeFromFfprobe('1920,1080,90'),
      const ItemListPixelSize(1080, 1920),
    );
  });
}
