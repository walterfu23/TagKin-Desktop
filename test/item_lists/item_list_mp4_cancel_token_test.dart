import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';

void main() {
  test('checkpoint waits while paused and continues on resume', () async {
    final token = ItemListMp4CancelToken();
    token.pause();
    var finished = false;
    final pending = token.checkpoint().then((_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    expect(token.isPaused, isTrue);
    token.resume();
    await pending;
    expect(finished, isTrue);
    expect(token.isPaused, isFalse);
  });

  test('cancel while paused unblocks checkpoint', () async {
    final token = ItemListMp4CancelToken();
    token.pause();
    final pending = token.checkpoint();
    token.cancel();
    await expectLater(pending, throwsA(isA<ItemListMp4CancelledException>()));
  });

  test('pause and cancel signal a fake process', () async {
    final signals = <ProcessSignal>[];
    final token = ItemListMp4CancelToken();
    token.attachSignalForTest(signals.add);
    token.pause();
    token.resume();
    token.pause();
    token.cancel();
    if (Platform.isWindows) {
      expect(signals, [ProcessSignal.sigkill]);
    } else {
      expect(signals, [
        ProcessSignal.sigstop,
        ProcessSignal.sigcont,
        ProcessSignal.sigstop,
        ProcessSignal.sigcont,
        ProcessSignal.sigkill,
      ]);
    }
  });

  test('pause stops a live process and cancel kills it', () async {
    if (Platform.isWindows) return;
    final process = await Process.start('/bin/sleep', ['30']);
    addTearDown(() {
      try {
        process.kill();
      } catch (_) {}
    });
    final token = ItemListMp4CancelToken();
    token.attach(process);
    token.pause();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final ps = await Process.run('ps', ['-o', 'state=', '-p', '${process.pid}']);
    expect(ps.stdout.toString().trim(), startsWith('T'));
    token.cancel();
    final code = await process.exitCode.timeout(const Duration(seconds: 2));
    expect(code, isNot(0));
  });
}
