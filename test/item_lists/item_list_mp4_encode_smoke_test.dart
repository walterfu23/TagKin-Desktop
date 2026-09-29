import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart';
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
    final wavRun = await Process.run(tools.ffmpeg, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=44100:cl=stereo',
      '-t',
      '3',
      wav,
    ]);
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

  test('photo, key period, photo dissolve encodes a non-empty MP4', () async {
    final tools = resolveFfmpegTools();
    if (tools == null) return;

    final tmp = await Directory.systemTemp.createTemp('mp4_smoke_mix_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    final photos = <File>[];
    for (var i = 0; i < 4; i++) {
      final file = File(p.join(tmp.path, 'p$i.jpg'));
      await file.writeAsBytes(_jpeg(r: 40 * i, g: 80, b: 160));
      photos.add(file);
    }
    final video = p.join(tmp.path, 'clip.mp4');
    final videoRun = await Process.run(tools.ffmpeg, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=green:s=64x48:d=0.5',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=44100:cl=stereo',
      '-shortest',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      video,
    ]);
    expect(videoRun.exitCode, 0, reason: '${videoRun.stderr}');

    final wav = p.join(tmp.path, 'silent.wav');
    final wavRun = await Process.run(tools.ffmpeg, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=44100:cl=stereo',
      '-t',
      '2',
      wav,
    ]);
    expect(wavRun.exitCode, 0, reason: '${wavRun.stderr}');

    final timeline = itemListNleTimeline(
      entries: [
        fixtureEntry(itemId: 'p1'),
        fixtureEntry(itemId: 'p2'),
        fixtureEntry(
          itemId: 'v1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp1',
          startMs: 0,
          endMs: 400,
        ),
        fixtureEntry(itemId: 'p3'),
        fixtureEntry(itemId: 'p4'),
      ],
      itemsById: {
        'p1': fixtureItem(
          id: 'p1',
          sourceRef: Uri.file(photos[0].path).toString(),
        ),
        'p2': fixtureItem(
          id: 'p2',
          sourceRef: Uri.file(photos[1].path).toString(),
        ),
        'v1': fixtureItem(
          id: 'v1',
          type: ItemType.video,
          sourceRef: Uri.file(video).toString(),
        ),
        'p3': fixtureItem(
          id: 'p3',
          sourceRef: Uri.file(photos[2].path).toString(),
        ),
        'p4': fixtureItem(
          id: 'p4',
          sourceRef: Uri.file(photos[3].path).toString(),
        ),
      },
      stillDurationSeconds: 0.4,
      transitionSeconds: 0.1,
    );
    final out = p.join(tmp.path, 'out.mp4');
    await itemListRenderMp4(
      timeline: timeline,
      audioPath: wav,
      outputPath: out,
      sequenceWidth: 160,
      sequenceHeight: 120,
      scaleToFit: true,
      useMacSavePanel: false,
    );
    final encoded = File(out);
    expect(encoded.existsSync(), isTrue);
    expect(encoded.lengthSync(), greaterThan(1000));
  });

  test('photo MP4 ends on white, with and without a soundtrack', () async {
    final tools = resolveFfmpegTools();
    if (tools == null) return;

    final tmp = await Directory.systemTemp.createTemp('mp4_smoke_white_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final photo = File(p.join(tmp.path, 'red.jpg'));
    await photo.writeAsBytes(_jpeg(r: 220, g: 20, b: 20));
    final wav = p.join(tmp.path, 'silent.wav');
    final wavRun = await Process.run(tools.ffmpeg, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=44100:cl=stereo',
      '-t',
      '4',
      wav,
    ]);
    expect(wavRun.exitCode, 0, reason: '${wavRun.stderr}');

    final timeline = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: Uri.file(photo.path).toString()),
      },
      stillDurationSeconds: 0.5,
      endFadeSeconds: kItemListNleEndFadeSeconds,
    );
    expect(timeline.duration, 105);

    final withMusic = p.join(tmp.path, 'with.mp4');
    await itemListRenderMp4(
      timeline: timeline,
      audioPath: wav,
      outputPath: withMusic,
      sequenceWidth: 64,
      sequenceHeight: 48,
      scaleToFit: true,
      useMacSavePanel: false,
    );
    await _expectWhiteEnding(
      ffmpeg: tools.ffmpeg,
      ffprobe: tools.ffprobe,
      path: withMusic,
      seconds: 3.5,
    );

    final silent = p.join(tmp.path, 'silent.mp4');
    await itemListRenderMp4(
      timeline: timeline,
      audioPath: null,
      outputPath: silent,
      sequenceWidth: 64,
      sequenceHeight: 48,
      scaleToFit: true,
      useMacSavePanel: false,
    );
    await _expectWhiteEnding(
      ffmpeg: tools.ffmpeg,
      ffprobe: tools.ffprobe,
      path: silent,
      seconds: 3.5,
    );
  });

  test('key period MP4 ends on white, with and without a soundtrack', () async {
    final tools = resolveFfmpegTools();
    if (tools == null) return;

    final tmp = await Directory.systemTemp.createTemp('mp4_smoke_white_kp_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final video = p.join(tmp.path, 'clip.mp4');
    final videoRun = await Process.run(tools.ffmpeg, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=blue:s=64x48:d=0.4',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=44100:cl=stereo',
      '-shortest',
      '-c:v',
      'libx264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      video,
    ]);
    expect(videoRun.exitCode, 0, reason: '${videoRun.stderr}');
    final wav = p.join(tmp.path, 'silent.wav');
    final wavRun = await Process.run(tools.ffmpeg, [
      '-y',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=44100:cl=stereo',
      '-t',
      '4',
      wav,
    ]);
    expect(wavRun.exitCode, 0, reason: '${wavRun.stderr}');

    final timeline = itemListNleTimeline(
      entries: [
        fixtureEntry(
          itemId: 'v1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp1',
          startMs: 0,
          endMs: 400,
        ),
      ],
      itemsById: {
        'v1': fixtureItem(
          id: 'v1',
          type: ItemType.video,
          sourceRef: Uri.file(video).toString(),
        ),
      },
      endFadeSeconds: kItemListNleEndFadeSeconds,
    );

    final withMusic = p.join(tmp.path, 'with.mp4');
    await itemListRenderMp4(
      timeline: timeline,
      audioPath: wav,
      outputPath: withMusic,
      sequenceWidth: 64,
      sequenceHeight: 48,
      scaleToFit: true,
      useMacSavePanel: false,
    );
    await _expectWhiteEnding(
      ffmpeg: tools.ffmpeg,
      ffprobe: tools.ffprobe,
      path: withMusic,
      seconds: timeline.duration / kItemListNleTimebase,
    );

    final silent = p.join(tmp.path, 'silent.mp4');
    await itemListRenderMp4(
      timeline: timeline,
      audioPath: null,
      outputPath: silent,
      sequenceWidth: 64,
      sequenceHeight: 48,
      scaleToFit: true,
      useMacSavePanel: false,
    );
    await _expectWhiteEnding(
      ffmpeg: tools.ffmpeg,
      ffprobe: tools.ffprobe,
      path: silent,
      seconds: timeline.duration / kItemListNleTimebase,
    );
  });
}

Future<void> _expectWhiteEnding({
  required String ffmpeg,
  required String ffprobe,
  required String path,
  required double seconds,
}) async {
  final encoded = File(path);
  expect(encoded.existsSync(), isTrue);
  expect(encoded.lengthSync(), greaterThan(1000));
  final probed = await Process.run(ffprobe, [
    '-v',
    'error',
    '-show_entries',
    'format=duration',
    '-of',
    'csv=p=0',
    path,
  ]);
  expect(probed.exitCode, 0, reason: '${probed.stderr}');
  final duration = double.parse((probed.stdout as String).trim());
  expect(duration, closeTo(seconds, 0.15));

  final png = '$path.png';
  final frame = await Process.run(ffmpeg, [
    '-y',
    '-sseof',
    '-0.05',
    '-i',
    path,
    '-frames:v',
    '1',
    png,
  ]);
  expect(frame.exitCode, 0, reason: '${frame.stderr}');
  final image = img.decodePng(await File(png).readAsBytes());
  expect(image, isNotNull);
  final pixel = image!.getPixel(image.width ~/ 2, image.height ~/ 2);
  expect(pixel.r, greaterThan(240));
  expect(pixel.g, greaterThan(240));
  expect(pixel.b, greaterThan(240));
}
