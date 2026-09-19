import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/prepass/ffmpeg_resolve.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

Uint8List _jpeg({required int r, required int g, required int b}) {
  final image = img.Image(width: 64, height: 48);
  img.fill(image, color: img.ColorRgb8(r, g, b));
  return Uint8List.fromList(img.encodeJpg(image, quality: 90));
}

void main() {
  test('itemListMp4ProgressLabel names each phase', () {
    expect(
      itemListMp4ProgressLabel(
        const ItemListMp4Progress(phase: ItemListMp4Phase.staging),
      ),
      'Preparing files…',
    );
    expect(
      itemListMp4ProgressLabel(
        const ItemListMp4Progress(
          phase: ItemListMp4Phase.encodingClips,
          clipIndex: 0,
          clipCount: 3,
        ),
      ),
      'Encoding clip 1 of 3…',
    );
    expect(
      itemListMp4ProgressLabel(
        const ItemListMp4Progress(
          phase: ItemListMp4Phase.encodingClips,
          clipIndex: 2,
          clipCount: 3,
        ),
      ),
      'Encoding clip 2 of 3…',
    );
    expect(
      itemListMp4ProgressLabel(
        const ItemListMp4Progress(phase: ItemListMp4Phase.assembling),
      ),
      'Composing video…',
    );
    expect(
      itemListMp4ProgressLabel(
        const ItemListMp4Progress(phase: ItemListMp4Phase.writingOut),
      ),
      'Writing file…',
    );
  });

  test('two-still MP4 encode writes clips and a non-empty assemble', () async {
    final tools = resolveFfmpegTools();
    if (tools == null) {
      return;
    }

    final tmp = await Directory.systemTemp.createTemp('mp4_smoke_');
    final dump = Directory(kItemListMp4DumpDir);
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    final a = File(p.join(tmp.path, 'a.jpg'));
    final b = File(p.join(tmp.path, 'b.jpg'));
    await a.writeAsBytes(_jpeg(r: 200, g: 40, b: 40));
    await b.writeAsBytes(_jpeg(r: 40, g: 40, b: 200));

    final wav = p.join(tmp.path, 'silent.wav');
    final wavRun = await Process.run(
      tools.ffmpeg,
      [
        '-y',
        '-f',
        'lavfi',
        '-i',
        'anullsrc=r=44100:cl=stereo',
        '-t',
        '3',
        wav,
      ],
    );
    expect(wavRun.exitCode, 0, reason: '${wavRun.stderr}');

    final timeline = itemListNleTimeline(
      entries: [
        fixtureEntry(itemId: 'p1'),
        fixtureEntry(itemId: 'p2'),
      ],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: Uri.file(a.path).toString()),
        'p2': fixtureItem(id: 'p2', sourceRef: Uri.file(b.path).toString()),
      },
      stillDurationSeconds: 0.5,
      transitionSeconds: 0.2,
    );
    final out = p.join(tmp.path, 'out.mp4');
    final phases = <ItemListMp4Phase>[];
    await itemListRenderMp4(
      timeline: timeline,
      audioPath: wav,
      outputPath: out,
      sequenceWidth: 320,
      sequenceHeight: 240,
      scaleToFit: true,
      useMacSavePanel: false,
      onProgress: (progress) => phases.add(progress.phase),
    );
    expect(
      phases,
      containsAllInOrder([
        ItemListMp4Phase.staging,
        ItemListMp4Phase.encodingClips,
        ItemListMp4Phase.assembling,
        ItemListMp4Phase.writingOut,
      ]),
    );

    final encoded = File(out);
    expect(encoded.existsSync(), isTrue);
    expect(encoded.lengthSync(), greaterThan(1000));
    expect(File(p.join(dump.path, 'ffmpeg.log')).existsSync(), isTrue);
    expect(File(p.join(dump.path, 'clip-0.mp4')).lengthSync(), greaterThan(0));
    expect(File(p.join(dump.path, 'clip-1.mp4')).lengthSync(), greaterThan(0));
  });
}
