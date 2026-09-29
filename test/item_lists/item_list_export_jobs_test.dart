import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/item_lists_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_jobs.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';

ItemListMp4ExportRequest _request(String path) {
  return ItemListMp4ExportRequest(
    entries: const [],
    itemsById: const {},
    outputPath: path,
    audioPath: '/tmp/a.wav',
  );
}

Future<void> _writeOut(String path) {
  return File(path).writeAsBytes(const [1, 2, 3, 4, 5, 6, 7, 8]);
}

void main() {
  test('two jobs progress independently and a third waits', () async {
    final gates = [Completer<void>(), Completer<void>(), Completer<void>()];
    final started = <int>[];
    final dir = Directory.systemTemp.createTempSync('tagkin-jobs-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = [for (var i = 0; i < 3; i++) '${dir.path}/out-$i.mp4'];
    final manager = ItemListExportJobManager(
      maxConcurrentJobs: 2,
      renderMp4:
          ({
            required timeline,
            required audioPath,
            required outputPath,
            required sequenceWidth,
            required sequenceHeight,
            required scaleToFit,
            soundtrackDuck = 0.05,
            onProgress,
            cancel,
            macSaveHandle,
          }) async {
            final index = paths.indexOf(outputPath);
            started.add(index);
            onProgress?.call(
              ItemListMp4Progress(
                phase: ItemListMp4Phase.encodingClips,
                clipIndex: index + 1,
                clipCount: 3,
              ),
            );
            await gates[index].future;
            cancel?.throwIfCancelled();
            await _writeOut(outputPath);
          },
    );
    addTearDown(manager.dispose);

    final jobs = [for (final path in paths) manager.start(_request(path))];
    await _until(() => started.length >= 2);
    expect(started.toSet(), {0, 1});
    expect(jobs[2].state, ItemListExportJobState.queued);
    expect(jobs[2].progressLabel, 'Waiting…');
    expect(jobs[0].progressLabel, contains('Encoding clip'));
    expect(jobs[1].phase, ItemListMp4Phase.encodingClips);

    gates[0].complete();
    await jobs[0].completed;
    expect(jobs[0].state, ItemListExportJobState.done);
    await _until(() => started.contains(2));
    expect(jobs[2].state, ItemListExportJobState.running);
    gates[1].complete();
    gates[2].complete();
    await jobs[1].completed;
    await jobs[2].completed;
    expect(jobs[1].state, ItemListExportJobState.done);
    expect(jobs[2].state, ItemListExportJobState.done);
  });

  test('cancelling one job leaves the other running', () async {
    final gates = [Completer<void>(), Completer<void>()];
    final dir = Directory.systemTemp.createTempSync('tagkin-jobs-cancel-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = ['${dir.path}/a.mp4', '${dir.path}/b.mp4'];
    final manager = ItemListExportJobManager(
      maxConcurrentJobs: 2,
      renderMp4:
          ({
            required timeline,
            required audioPath,
            required outputPath,
            required sequenceWidth,
            required sequenceHeight,
            required scaleToFit,
            soundtrackDuck = 0.05,
            onProgress,
            cancel,
            macSaveHandle,
          }) async {
            onProgress?.call(
              const ItemListMp4Progress(phase: ItemListMp4Phase.staging),
            );
            final index = paths.indexOf(outputPath);
            await gates[index].future;
            cancel?.throwIfCancelled();
            await _writeOut(outputPath);
          },
    );
    addTearDown(manager.dispose);
    final first = manager.start(_request(paths[0]));
    final second = manager.start(_request(paths[1]));
    await _until(() => first.phase != null && second.phase != null);
    manager.cancel(first.id);
    gates[0].complete();
    gates[1].complete();
    await first.completed;
    await second.completed;
    expect(first.state, ItemListExportJobState.cancelled);
    expect(second.state, ItemListExportJobState.done);
  });

  test('pause blocks the next clip until continue', () async {
    final events = <String>[];
    final entered = Completer<void>();
    final hold = Completer<void>();
    final dir = Directory.systemTemp.createTempSync('tagkin-jobs-pause-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/out.mp4';
    final manager = ItemListExportJobManager(
      renderMp4:
          ({
            required timeline,
            required audioPath,
            required outputPath,
            required sequenceWidth,
            required sequenceHeight,
            required scaleToFit,
            soundtrackDuck = 0.05,
            onProgress,
            cancel,
            macSaveHandle,
          }) async {
            events.add('clip-1');
            if (!entered.isCompleted) entered.complete();
            await hold.future;
            await cancel!.checkpoint();
            events.add('clip-2');
            await _writeOut(outputPath);
          },
    );
    addTearDown(manager.dispose);
    final job = manager.start(_request(path));
    await entered.future;
    manager.pause(job.id);
    hold.complete();
    await Future<void>.delayed(Duration.zero);
    expect(job.state, ItemListExportJobState.paused);
    expect(events, ['clip-1']);
    manager.resume(job.id);
    await job.completed;
    expect(events, ['clip-1', 'clip-2']);
    expect(job.state, ItemListExportJobState.done);
  });

  test('cancel while paused terminates the job', () async {
    final entered = Completer<void>();
    final hold = Completer<void>();
    final dir = Directory.systemTemp.createTempSync(
      'tagkin-jobs-pause-cancel-',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/out.mp4';
    final manager = ItemListExportJobManager(
      renderMp4:
          ({
            required timeline,
            required audioPath,
            required outputPath,
            required sequenceWidth,
            required sequenceHeight,
            required scaleToFit,
            soundtrackDuck = 0.05,
            onProgress,
            cancel,
            macSaveHandle,
          }) async {
            if (!entered.isCompleted) entered.complete();
            await hold.future;
            await cancel!.checkpoint();
            await _writeOut(outputPath);
          },
    );
    addTearDown(manager.dispose);
    final job = manager.start(_request(path));
    await entered.future;
    manager.pause(job.id);
    hold.complete();
    await Future<void>.delayed(Duration.zero);
    manager.cancel(job.id);
    await job.completed;
    expect(job.state, ItemListExportJobState.cancelled);
  });

  test('pausing a running export starts the one that is waiting', () async {
    final gates = [Completer<void>(), Completer<void>(), Completer<void>()];
    final started = <int>[];
    final dir = Directory.systemTemp.createTempSync('tagkin-jobs-pause-slot-');
    addTearDown(() {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = [for (var i = 0; i < 3; i++) '${dir.path}/out-$i.mp4'];
    final manager = ItemListExportJobManager(
      maxConcurrentJobs: 2,
      renderMp4: _gatedRender(paths: paths, gates: gates, started: started),
    );
    addTearDown(manager.dispose);

    final jobs = [for (final path in paths) manager.start(_request(path))];
    await _until(() => started.length >= 2);
    expect(jobs[2].progressLabel, 'Waiting…');

    manager.pause(jobs[0].id);
    await _until(() => started.contains(2));
    expect(jobs[0].state, ItemListExportJobState.paused);
    expect(jobs[0].control.isPaused, isTrue);
    expect(jobs[2].state, ItemListExportJobState.running);

    manager.resume(jobs[0].id);
    expect(jobs[0].state, ItemListExportJobState.queued);
    expect(jobs[0].control.isPaused, isTrue);
    expect(jobs[0].progressLabel, 'Waiting · Encoding clip 1 of 3…');

    gates[1].complete();
    await _until(() => jobs[0].state == ItemListExportJobState.running);
    expect(jobs[0].control.isPaused, isFalse);
    gates[0].complete();
    gates[2].complete();
    await jobs[0].completed;
    await jobs[1].completed;
    await jobs[2].completed;
    expect(jobs[0].state, ItemListExportJobState.done);
    expect(jobs[2].state, ItemListExportJobState.done);
  });

  test(
    'continued exports resume in order ahead of one that has not started',
    () async {
      final gates = List.generate(5, (_) => Completer<void>());
      final started = <int>[];
      final dir = Directory.systemTemp.createTempSync('tagkin-jobs-order-');
      addTearDown(() {
        for (final gate in gates) {
          if (!gate.isCompleted) gate.complete();
        }
      });
      addTearDown(() => dir.deleteSync(recursive: true));
      final paths = [for (var i = 0; i < 5; i++) '${dir.path}/out-$i.mp4'];
      final manager = ItemListExportJobManager(
        maxConcurrentJobs: 2,
        renderMp4: _gatedRender(paths: paths, gates: gates, started: started),
      );
      addTearDown(manager.dispose);

      final jobs = [
        for (final path in paths.take(4)) manager.start(_request(path)),
      ];
      await _until(() => started.toSet().containsAll([0, 1]));
      manager.pause(jobs[0].id);
      await _until(() => started.contains(2));
      manager.pause(jobs[1].id);
      await _until(() => started.contains(3));
      expect(jobs[2].state, ItemListExportJobState.running);
      expect(jobs[3].state, ItemListExportJobState.running);

      final fresh = manager.start(_request(paths[4]));
      expect(fresh.state, ItemListExportJobState.queued);
      expect(fresh.started, isFalse);

      manager.resume(jobs[0].id);
      manager.resume(jobs[1].id);
      expect(jobs[0].state, ItemListExportJobState.queued);
      expect(jobs[1].state, ItemListExportJobState.queued);
      expect(jobs[0].control.isPaused, isTrue);
      expect(jobs[1].control.isPaused, isTrue);

      gates[2].complete();
      await _until(() => jobs[0].state == ItemListExportJobState.running);
      expect(jobs[0].control.isPaused, isFalse);
      expect(jobs[1].state, ItemListExportJobState.queued);
      expect(jobs[1].control.isPaused, isTrue);
      expect(fresh.state, ItemListExportJobState.queued);
      expect(fresh.started, isFalse);

      gates[0].complete();
      gates[3].complete();
      await jobs[0].completed;
      await jobs[3].completed;
      await _until(() => jobs[1].state == ItemListExportJobState.running);
      await _until(() => fresh.started);
      gates[1].complete();
      gates[4].complete();
      await jobs[1].completed;
      await jobs[2].completed;
      await fresh.completed;
    },
  );

  test('cancel ends a continued export that is waiting for a slot', () async {
    final gates = [Completer<void>(), Completer<void>(), Completer<void>()];
    final started = <int>[];
    final dir = Directory.systemTemp.createTempSync('tagkin-jobs-wait-cancel-');
    addTearDown(() {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
    });
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = [for (var i = 0; i < 3; i++) '${dir.path}/out-$i.mp4'];
    final manager = ItemListExportJobManager(
      maxConcurrentJobs: 2,
      renderMp4: _gatedRender(paths: paths, gates: gates, started: started),
    );
    addTearDown(manager.dispose);

    final jobs = [for (final path in paths) manager.start(_request(path))];
    await _until(() => started.toSet().containsAll([0, 1]));
    manager.pause(jobs[0].id);
    await _until(() => started.contains(2));
    gates[0].complete();
    await Future<void>.delayed(Duration.zero);
    manager.resume(jobs[0].id);
    expect(jobs[0].state, ItemListExportJobState.queued);
    expect(jobs[0].control.isPaused, isTrue);

    manager.cancel(jobs[0].id);
    await jobs[0].completed;
    expect(jobs[0].state, ItemListExportJobState.cancelled);
    expect(jobs[1].state, ItemListExportJobState.running);
    expect(jobs[2].state, ItemListExportJobState.running);
  });

  test('cancelAll cancels every active job', () async {
    final gates = [Completer<void>(), Completer<void>()];
    final dir = Directory.systemTemp.createTempSync('tagkin-jobs-all-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final paths = ['${dir.path}/a.mp4', '${dir.path}/b.mp4'];
    final manager = ItemListExportJobManager(
      maxConcurrentJobs: 2,
      renderMp4:
          ({
            required timeline,
            required audioPath,
            required outputPath,
            required sequenceWidth,
            required sequenceHeight,
            required scaleToFit,
            soundtrackDuck = 0.05,
            onProgress,
            cancel,
            macSaveHandle,
          }) async {
            onProgress?.call(
              const ItemListMp4Progress(phase: ItemListMp4Phase.staging),
            );
            final index = paths.indexOf(outputPath);
            await gates[index].future;
            cancel?.throwIfCancelled();
            await _writeOut(outputPath);
          },
    );
    addTearDown(manager.dispose);
    final jobs = [for (final path in paths) manager.start(_request(path))];
    await _until(() => jobs.every((job) => job.phase != null));
    final pending = manager.cancelAll();
    for (final gate in gates) {
      gate.complete();
    }
    await pending;
    expect(
      jobs.every((job) => job.state == ItemListExportJobState.cancelled),
      isTrue,
    );
    expect(manager.hasActive, isFalse);
  });

  test('MP4 job renders with a null soundtrack', () async {
    String? seenAudio = 'unset';
    final dir = Directory.systemTemp.createTempSync('tagkin-jobs-nomusic-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/out.mp4';
    final manager = ItemListExportJobManager(
      renderMp4:
          ({
            required timeline,
            required audioPath,
            required outputPath,
            required sequenceWidth,
            required sequenceHeight,
            required scaleToFit,
            soundtrackDuck = 0.05,
            onProgress,
            cancel,
            macSaveHandle,
          }) async {
            seenAudio = audioPath;
            await _writeOut(outputPath);
          },
    );
    addTearDown(manager.dispose);
    final job = manager.start(
      ItemListMp4ExportRequest(
        entries: const [],
        itemsById: const {},
        outputPath: path,
      ),
    );
    await job.completed;
    expect(job.state, ItemListExportJobState.done);
    expect(seenAudio, isNull);
    expect(job.request.audioPath, isNull);
  });

  test('MP4 jobs record with-music and without-music formats', () async {
    final recorded = <RecordItemListExport>[];
    final repo = _RecordingItemLists(recorded);
    final dir = Directory.systemTemp.createTempSync('tagkin-jobs-record-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final manager = ItemListExportJobManager(
      itemListsRepository: repo,
      renderMp4:
          ({
            required timeline,
            required audioPath,
            required outputPath,
            required sequenceWidth,
            required sequenceHeight,
            required scaleToFit,
            soundtrackDuck = 0.05,
            onProgress,
            cancel,
            macSaveHandle,
          }) async {
            await _writeOut(outputPath);
          },
    );
    addTearDown(manager.dispose);

    final withMusic = manager.start(_request('${dir.path}/with.mp4'));
    await withMusic.completed;
    final withoutMusic = manager.start(
      ItemListMp4ExportRequest(
        entries: const [],
        itemsById: const {},
        outputPath: '${dir.path}/without.mp4',
      ),
    );
    await withoutMusic.completed;
    expect(recorded.map((row) => row.format.wire).toList(), [
      'mp4WithMusic',
      'mp4WithoutMusic',
    ]);
  });
}

class _RecordingItemLists extends ItemListsRepository {
  _RecordingItemLists(this.recorded)
    : super(ApiClient(baseUrl: 'http://api.test', tokenProvider: () => 'tok'));

  final List<RecordItemListExport> recorded;

  @override
  Future<ItemListExport> recordExport(RecordItemListExport body) async {
    recorded.add(body);
    return ItemListExport(
      id: '11111111-1111-1111-1111-111111111111',
      format: body.format,
      photoCount: body.photoCount,
      keyPeriodCount: body.keyPeriodCount,
      outputDurationMs: body.outputDurationMs,
      encodeWallMs: body.encodeWallMs,
    );
  }
}

ItemListMp4Renderer _gatedRender({
  required List<String> paths,
  required List<Completer<void>> gates,
  required List<int> started,
}) {
  return ({
    required timeline,
    required audioPath,
    required outputPath,
    required sequenceWidth,
    required sequenceHeight,
    required scaleToFit,
    soundtrackDuck = 0.05,
    onProgress,
    cancel,
    macSaveHandle,
  }) async {
    final index = paths.indexOf(outputPath);
    started.add(index);
    onProgress?.call(
      ItemListMp4Progress(
        phase: ItemListMp4Phase.encodingClips,
        clipIndex: 1,
        clipCount: 3,
      ),
    );
    await gates[index].future;
    await cancel!.checkpoint();
    await _writeOut(outputPath);
  };
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 50; i++) {
    if (done()) return;
    await Future<void>.delayed(Duration.zero);
  }
  fail('timed out waiting for export jobs');
}
