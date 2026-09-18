import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_filter.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_materialize.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

Uint8List _tinyJpeg() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgb8(20, 80, 160));
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  late Directory tmp;
  late FolderBookmarkStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mp4_mat_');
    store = FolderBookmarkStore(supportDir: Directory(p.join(tmp.path, 'bm')));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('itemListMp4StillNeedsJpeg is true for HEIC, false for JPEG/PNG', () {
    expect(itemListMp4StillNeedsJpeg('/a/shot.heic'), isTrue);
    expect(itemListMp4StillNeedsJpeg('/a/shot.heif'), isTrue);
    expect(itemListMp4StillNeedsJpeg('/a/shot.jpg'), isFalse);
    expect(itemListMp4StillNeedsJpeg('/a/shot.png'), isFalse);
  });

  test('JPEG still is copied into destDir; plan uses the copy', () async {
    final jpeg = _tinyJpeg();
    final src = File(p.join(tmp.path, 'shot.jpg'));
    await src.writeAsBytes(jpeg);
    final destDir = Directory(p.join(tmp.path, 'out'));
    await destDir.create();

    final timeline = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: Uri.file(src.path).toString()),
      },
    );
    final byOriginal = await itemListMaterializeMp4Inputs(
      clips: timeline.clips,
      destDir: destDir.path,
      bookmarks: store,
    );
    expect(byOriginal[src.path], isNot(src.path));
    expect(File(byOriginal[src.path]!).readAsBytesSync(), jpeg);

    final plan = itemListMp4Plan(
      timeline: itemListMp4TimelineWithMaterializedPaths(timeline, byOriginal),
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    expect(plan.inputs.single.path, byOriginal[src.path]);
    expect(plan.inputs.single.path, isNot(src.path));
  });

  test('HEIC still is written as JPEG via injected converter', () async {
    final src = File(p.join(tmp.path, 'shot.heic'));
    await src.writeAsBytes([1, 2, 3, 4]);
    final jpeg = _tinyJpeg();
    final destDir = Directory(p.join(tmp.path, 'out'));
    await destDir.create();
    var converted = false;

    final timeline = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: Uri.file(src.path).toString()),
      },
    );
    final byOriginal = await itemListMaterializeMp4Inputs(
      clips: timeline.clips,
      destDir: destDir.path,
      bookmarks: store,
      stillToJpeg: (raw) async {
        converted = true;
        expect(raw, [1, 2, 3, 4]);
        return jpeg;
      },
    );
    expect(converted, isTrue);
    final dest = byOriginal[src.path]!;
    expect(p.extension(dest), '.jpg');
    expect(File(dest).readAsBytesSync(), jpeg);
  });

  test('missing source throws ItemListMp4RenderException', () async {
    final missing = p.join(tmp.path, 'gone.jpg');
    final destDir = Directory(p.join(tmp.path, 'out'));
    await destDir.create();
    final timeline = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: Uri.file(missing).toString()),
      },
    );
    expect(
      () => itemListMaterializeMp4Inputs(
        clips: timeline.clips,
        destDir: destDir.path,
        bookmarks: store,
      ),
      throwsA(isA<ItemListMp4RenderException>()),
    );
  });
}
