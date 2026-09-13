import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_hover_preview.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

import 'fake_comments_repository.dart';
import 'fake_items_repository.dart';

LibraryTableController _controller(FakeItemsRepository items) {
  return LibraryTableController(
    itemsRepository: items,
    commentsRepository: FakeCommentsRepository(),
    thumbCache: LocalThumbCache(),
    knowledgeConcurrency: 1,
  );
}

class _FakeVideoSession implements HoverPreviewVideoSession {
  _FakeVideoSession();
  final StreamController<Duration> positions =
      StreamController<Duration>.broadcast();
  final List<Duration> seeks = <Duration>[];
  var playCount = 0;
  var disposed = false;

  @override
  Widget get view =>
      const ColoredBox(key: Key('fake-hover-video'), color: Colors.black);

  @override
  Stream<Duration> get position => positions.stream;

  @override
  Stream<Size> get videoSize => Stream<Size>.value(const Size(1920, 1080));

  @override
  Future<void> seek(Duration to) async {
    seeks.add(to);
  }

  @override
  Future<void> play() async {
    playCount++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await positions.close();
  }
}

Future<TestGesture> _hoverThumb(WidgetTester tester, String itemId) async {
  final finder = find.byKey(Key('item-hover-preview-$itemId'));
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(tester.getCenter(finder));
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump();
  await tester.pump();
  return gesture;
}

Future<void> _awaitKnowledge(
  WidgetTester tester,
  LibraryTableController c,
) async {
  for (var i = 0; i < 20; i++) {
    if (c.allRows.every((r) => r.knowledgeLoaded)) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
}

void main() {
  test('fitHoverPreviewSize preserves aspect ratio inside max', () {
    expect(
      fitHoverPreviewSize(const Size(4000, 3000), const Size(840, 720)),
      const Size(840, 630),
    );
    expect(
      fitHoverPreviewSize(const Size(1080, 1920), const Size(840, 720)),
      const Size(405, 720),
    );
    expect(
      fitHoverPreviewSize(const Size(100, 100), const Size(840, 720)),
      const Size(720, 720),
    );
    expect(
      fitHoverPreviewSize(Size.zero, const Size(840, 720)),
      kHoverPreviewFallbackSize,
    );
  });

  test('hoverPreviewStopAt uses the earliest-start period end', () {
    expect(
      hoverPreviewStopAt(keyPeriods: const []),
      kHoverPreviewFallbackVideoWindow,
    );
    expect(
      hoverPreviewStopAt(
        keyPeriods: [
          KeyPeriodKnowledge(
            id: 'b',
            itemId: 'v',
            startMs: 2000,
            endMs: 9000,
            tags: const [],
          ),
          KeyPeriodKnowledge(
            id: 'a',
            itemId: 'v',
            startMs: 0,
            endMs: 1800,
            tags: const [],
          ),
        ],
      ),
      const Duration(milliseconds: 1800),
    );
  });

  testWidgets('photo hover shows a larger still and hides on exit', (
    tester,
  ) async {
    final item = fixtureItem(id: 'p1', type: ItemType.photo);
    final controller = _controller(FakeItemsRepository(items: [item]));
    addTearDown(controller.dispose);
    final dummy = File('/tmp/unused.jpg');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ItemHoverPreview(
              item: item,
              controller: controller,
              hoverDelay: Duration.zero,
              resolveMedia: (_) async => LocalMediaResolution(
                status: LocalMediaStatus.available,
                file: dummy,
                path: dummy.path,
              ),
              buildPhoto: (file) => SizedBox(
                key: const Key('item-hover-preview-photo'),
                width: 400,
                height: 300,
                child: ColoredBox(color: Colors.orange, child: Text(file.path)),
              ),
              child: const SizedBox(
                width: 56,
                height: 56,
                child: ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('item-hover-preview-card')), findsNothing);
    final hover = await _hoverThumb(tester, 'p1');
    await tester.pump();
    expect(find.byKey(const Key('item-hover-preview-card')), findsOneWidget);
    expect(find.byKey(const Key('item-hover-preview-photo')), findsOneWidget);
    expect(
      tester
          .widget<Align>(find.byKey(const Key('item-hover-preview-align')))
          .alignment,
      Alignment.center,
    );

    await hover.moveTo(const Offset(-80, -80));
    await tester.pump();
    await tester.pump(kHoverPreviewHideDelay);
    expect(find.byKey(const Key('item-hover-preview-card')), findsNothing);
  });

  testWidgets('video hover plays until the first key period end', (
    tester,
  ) async {
    final item = fixtureItem(
      id: 'v1',
      type: ItemType.video,
      processingStatus: ProcessingStatus.tagged,
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {
        'v1': fixtureKnowledge(
          item: item,
          tags: const [],
          keyPeriods: [
            KeyPeriodKnowledge(
              id: 'kp1',
              itemId: 'v1',
              startMs: 0,
              endMs: 1800,
              tags: const [],
            ),
          ],
        ),
      },
    );
    final controller = _controller(items);
    addTearDown(controller.dispose);

    final session = _FakeVideoSession();
    final dummy = File('/tmp/unused.mp4');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ItemHoverPreview(
              item: item,
              controller: controller,
              hoverDelay: Duration.zero,
              resolveMedia: (_) async => LocalMediaResolution(
                status: LocalMediaStatus.available,
                file: dummy,
                path: dummy.path,
              ),
              openVideo: (_) async => session,
              child: const SizedBox(
                width: 56,
                height: 56,
                child: ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );
    await controller.load();
    await _awaitKnowledge(tester, controller);

    final hover = await _hoverThumb(tester, 'v1');
    await tester.pump();
    expect(find.byKey(const Key('item-hover-preview-video')), findsOneWidget);
    expect(session.playCount, 1);
    expect(session.seeks, contains(Duration.zero));

    session.positions.add(const Duration(milliseconds: 1800));
    await tester.pump();
    expect(session.seeks.last, Duration.zero);

    await hover.moveTo(const Offset(-80, -80));
    await tester.pump();
    await tester.pump(kHoverPreviewHideDelay);
    expect(session.disposed, isTrue);
    expect(find.byKey(const Key('item-hover-preview-card')), findsNothing);
  });

  testWidgets('video hover fetches key periods when the row is still warming', (
    tester,
  ) async {
    final item = fixtureItem(
      id: 'v2',
      type: ItemType.video,
      processingStatus: ProcessingStatus.tagged,
    );
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {
        'v2': fixtureKnowledge(
          item: item,
          tags: const [],
          keyPeriods: [
            KeyPeriodKnowledge(
              id: 'kp1',
              itemId: 'v2',
              startMs: 0,
              endMs: 1200,
              tags: const [],
            ),
          ],
        ),
      },
      onGetKnowledge: (_) => gate.future,
    );
    final controller = _controller(items);
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.allRows.single.knowledgeLoaded, isFalse);

    final session = _FakeVideoSession();
    final dummy = File('/tmp/unused.mp4');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ItemHoverPreview(
              item: item,
              controller: controller,
              hoverDelay: Duration.zero,
              fallbackVideoWindow: const Duration(seconds: 4),
              resolveMedia: (_) async => LocalMediaResolution(
                status: LocalMediaStatus.available,
                file: dummy,
                path: dummy.path,
              ),
              openVideo: (_) async => session,
              child: const SizedBox(
                width: 56,
                height: 56,
                child: ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );

    await _hoverThumb(tester, 'v2');
    await tester.pump();
    expect(session.playCount, 1);

    session.positions.add(const Duration(milliseconds: 1200));
    await tester.pump();
    expect(session.seeks.where((s) => s == Duration.zero).length, 1);

    gate.complete();
    await tester.pump();
    await tester.pump();
    session.positions.add(const Duration(milliseconds: 1200));
    await tester.pump();
    expect(
      session.seeks.where((s) => s == Duration.zero).length,
      greaterThan(1),
    );
  });

  testWidgets('hover preview shows a message when local media is missing', (
    tester,
  ) async {
    final item = fixtureItem(id: 'missing');
    final controller = _controller(FakeItemsRepository(items: [item]));
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ItemHoverPreview(
              item: item,
              controller: controller,
              hoverDelay: Duration.zero,
              resolveMedia: (_) async =>
                  const LocalMediaResolution(status: LocalMediaStatus.missing),
              child: const SizedBox(
                width: 56,
                height: 56,
                child: ColoredBox(color: Colors.grey),
              ),
            ),
          ),
        ),
      ),
    );

    await _hoverThumb(tester, 'missing');
    await tester.pump();
    expect(find.byKey(const Key('item-hover-preview-error')), findsOneWidget);
    expect(find.text('Local media not found.'), findsOneWidget);
  });
}
