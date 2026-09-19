import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';

void main() {
  test('software clip concurrency is 1–4; hardware is sequential', () {
    expect(
      itemListMp4ClipConcurrency(
        encoder: ItemListMp4EncoderKind.libx264,
        processorCount: 8,
      ),
      kItemListMp4MaxClipConcurrency,
    );
    expect(
      itemListMp4ClipConcurrency(
        encoder: ItemListMp4EncoderKind.libx264,
        processorCount: 2,
      ),
      2,
    );
    expect(
      itemListMp4ClipConcurrency(
        encoder: ItemListMp4EncoderKind.libx264,
        processorCount: 1,
      ),
      1,
    );
    expect(
      itemListMp4ClipConcurrency(
        encoder: ItemListMp4EncoderKind.videotoolbox,
        processorCount: 8,
      ),
      1,
    );
    expect(
      itemListMp4ClipConcurrency(
        encoder: ItemListMp4EncoderKind.mediaFoundation,
        processorCount: 16,
      ),
      1,
    );
  });

  test('itemListMp4RunWithConcurrency preserves order and caps workers', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    final results = await itemListMp4RunWithConcurrency<int>(
      count: 8,
      maxConcurrent: 3,
      run: (i) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(Duration(milliseconds: 15 + (i % 3) * 8));
        inFlight--;
        return i * 10;
      },
    );
    expect(results, [0, 10, 20, 30, 40, 50, 60, 70]);
    expect(maxInFlight, 3);
  });

  test('hardware encode failure retries once with libx264', () async {
    final tmp = await Directory.systemTemp.createTemp('mp4_fallback_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    final out = p.join(tmp.path, 'clip-0.mp4');
    final labels = <String>[];
    final codecs = <String>[];

    Future<({int exitCode, String stderr})> run({
      required String ffmpeg,
      required List<String> args,
      required StringBuffer log,
      required String label,
    }) async {
      labels.add(label);
      final c = args.indexOf('-c:v');
      codecs.add(c >= 0 && c + 1 < args.length ? args[c + 1] : '');
      if (label.endsWith('-libx264')) {
        await File(out).writeAsBytes([0, 1, 2, 3, 4, 5, 6, 7]);
        return (exitCode: 0, stderr: '');
      }
      return (exitCode: 1, stderr: 'vt failed');
    }

    final ran = await itemListMp4RunEncodeWithFallback(
      ffmpeg: 'ffmpeg',
      args: const ['-c:v', 'h264_videotoolbox', '-y', 'unused'],
      softwareArgs: const ['-c:v', 'libx264', '-preset', 'ultrafast'],
      encoder: ItemListMp4EncoderKind.videotoolbox,
      outputPath: out,
      log: StringBuffer(),
      label: 'clip-0',
      run: run,
    );
    expect(ran.exitCode, 0);
    expect(labels, ['clip-0', 'clip-0-libx264']);
    expect(codecs, ['h264_videotoolbox', 'libx264']);
    expect(File(out).lengthSync(), greaterThan(0));
  });

  test('libx264 failure does not retry', () async {
    final labels = <String>[];
    Future<({int exitCode, String stderr})> run({
      required String ffmpeg,
      required List<String> args,
      required StringBuffer log,
      required String label,
    }) async {
      labels.add(label);
      return (exitCode: 1, stderr: 'x264 failed');
    }

    final ran = await itemListMp4RunEncodeWithFallback(
      ffmpeg: 'ffmpeg',
      args: const ['-c:v', 'libx264'],
      softwareArgs: const ['-c:v', 'libx264', '-preset', 'ultrafast'],
      encoder: ItemListMp4EncoderKind.libx264,
      outputPath: '/tmp/does-not-exist-clip.mp4',
      log: StringBuffer(),
      label: 'clip-0',
      run: run,
    );
    expect(ran.exitCode, 1);
    expect(labels, ['clip-0']);
  });

  test('cancelled hardware encode does not fall back to libx264', () async {
    final labels = <String>[];
    final cancel = ItemListMp4CancelToken();
    Future<({int exitCode, String stderr})> run({
      required String ffmpeg,
      required List<String> args,
      required StringBuffer log,
      required String label,
    }) async {
      labels.add(label);
      cancel.cancel();
      throw ItemListMp4CancelledException();
    }

    await expectLater(
      itemListMp4RunEncodeWithFallback(
        ffmpeg: 'ffmpeg',
        args: const ['-c:v', 'h264_videotoolbox'],
        softwareArgs: const ['-c:v', 'libx264'],
        encoder: ItemListMp4EncoderKind.videotoolbox,
        outputPath: '/tmp/does-not-exist-clip.mp4',
        log: StringBuffer(),
        label: 'clip-0',
        run: run,
        cancel: cancel,
      ),
      throwsA(isA<ItemListMp4CancelledException>()),
    );
    expect(labels, ['clip-0']);
  });

  test('cancel token throwIfCancelled after cancel', () {
    final token = ItemListMp4CancelToken();
    token.throwIfCancelled();
    token.cancel();
    expect(
      token.throwIfCancelled,
      throwsA(isA<ItemListMp4CancelledException>()),
    );
  });

  test('hardware bitrate buckets 720p / 1080p / 4K', () {
    expect(
      itemListMp4HardwareBitrateMbps(
        sequenceWidth: 1280,
        sequenceHeight: 720,
      ),
      4,
    );
    expect(
      itemListMp4HardwareBitrateMbps(
        sequenceWidth: 1920,
        sequenceHeight: 1080,
      ),
      8,
    );
    expect(
      itemListMp4HardwareBitrateMbps(
        sequenceWidth: 3840,
        sequenceHeight: 2160,
      ),
      16,
    );
  });
}
