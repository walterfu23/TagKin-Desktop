import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
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
  final List<({Duration start, Duration stopAt})> clips =
      <({Duration start, Duration stopAt})>[];
  final List<Duration> seeks = <Duration>[];
  final List<String> calls = <String>[];
  var playCount = 0;
  var disposed = false;

  final List<bool> loops = <bool>[];
  final List<bool> showStillOffered = <bool>[];
  final StreamController<void> ended = StreamController<void>.broadcast();

  @override
  Widget buildView({VoidCallback? onShowStill}) {
    showStillOffered.add(onShowStill != null);
    return Stack(
      children: [
        const Positioned.fill(
          child: ColoredBox(key: Key('fake-hover-video'), color: Colors.black),
        ),
        if (onShowStill != null)
          Positioned(
            right: 8,
            bottom: 8,
            child: GestureDetector(
              key: const Key('hover-show-still'),
              behavior: HitTestBehavior.opaque,
              onTap: onShowStill,
              child: const SizedBox(width: 60, height: 24),
            ),
          ),
      ],
    );
  }

  @override
  Stream<void> get clipEnded => ended.stream;

  @override
  Stream<Size> get videoSize => Stream<Size>.value(const Size(1920, 1080));

  @override
  Future<void> prepare() async {
    calls.add('prepare');
  }

  @override
  Future<void> setClip(
    Duration start,
    Duration stopAt, {
    bool loop = true,
  }) async {
    calls.add('setClip');
    loops.add(loop);
    clips.add((start: start, stopAt: stopAt));
  }

  @override
  Future<void> seek(Duration to) async {
    calls.add('seek');
    seeks.add(to);
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playCount++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

Future<TestGesture> _hoverThumb(
  WidgetTester tester,
  String itemId, {
  String? periodId,
}) async {
  final finder = find.byKey(
    Key(
      periodId == null
          ? 'item-hover-preview-$itemId'
          : 'item-hover-preview-$itemId-kp-$periodId',
    ),
  );
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
  for (var i = 0; i < 50; i++) {
    if (c.allRows.isNotEmpty && c.allRows.every((r) => r.knowledgeLoaded)) {
      return;
    }
    await tester.pump();
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

  test('hoverPreviewWindow plays a specific period start to end', () {
    const period = KeyPeriodKnowledge(
      id: 'b',
      itemId: 'v',
      startMs: 2000,
      endMs: 9000,
      tags: [],
    );
    final window = hoverPreviewWindow(period: period);
    expect(window.start, const Duration(milliseconds: 2000));
    expect(window.stopAt, const Duration(milliseconds: 9000));
  });

  test('hoverPreviewWindow uses earliest period start, not file 0', () {
    final window = hoverPreviewWindow(
      keyPeriods: [
        KeyPeriodKnowledge(
          id: 'late',
          itemId: 'v',
          startMs: 9583,
          endMs: 42357,
          tags: const [],
        ),
      ],
    );
    expect(window.start, const Duration(milliseconds: 9583));
    expect(window.stopAt, const Duration(milliseconds: 42357));
  });

  test('hoverExactSeekCommand is mpv absolute+exact', () {
    expect(hoverExactSeekCommand(const Duration(milliseconds: 9583)), [
      'seek',
      hoverAbLoopTimestamp(const Duration(milliseconds: 9583)),
      'absolute+exact',
    ]);
  });

  test('hoverSeekPositionLanded treats in-span as landed', () {
    expect(
      hoverSeekPositionLanded(
        position: const Duration(milliseconds: 9583),
        start: const Duration(milliseconds: 9583),
        stopAt: const Duration(milliseconds: 42357),
      ),
      isTrue,
    );
    expect(
      hoverSeekPositionLanded(
        position: Duration.zero,
        start: const Duration(milliseconds: 9583),
        stopAt: const Duration(milliseconds: 42357),
      ),
      isFalse,
    );
  });

  test('hoverSeekStuckAtZero is true when a late start is still at 0', () {
    expect(
      hoverSeekStuckAtZero(
        position: Duration.zero,
        start: const Duration(milliseconds: 9583),
      ),
      isTrue,
    );
    expect(
      hoverSeekStuckAtZero(
        position: const Duration(milliseconds: 9583),
        start: const Duration(milliseconds: 9583),
      ),
      isFalse,
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

  testWidgets('edit-mode hover lists each face with its Who value', (
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
              faces: const [
                HoverPreviewFace(
                  number: 1,
                  region: TagRegion(yMin: 0.1, xMin: 0.2, yMax: 0.5, xMax: 0.6),
                  personName: 'Maya',
                ),
              ],
              resolveMedia: (_) async => LocalMediaResolution(
                status: LocalMediaStatus.available,
                file: dummy,
                path: dummy.path,
              ),
              buildPhoto: (file) => const SizedBox(
                key: Key('item-hover-preview-photo'),
                width: 400,
                height: 300,
              ),
              child: const SizedBox(width: 56, height: 56),
            ),
          ),
        ),
      ),
    );

    final hover = await _hoverThumb(tester, 'p1');
    await tester.pump();
    expect(find.byKey(const Key('hover-face-label-1')), findsOneWidget);
    expect(find.text('1 Maya'), findsOneWidget);
    await hover.moveTo(const Offset(-80, -80));
    await tester.pump(kHoverPreviewFaceHideDelay);
  });

  testWidgets('face hover card stays open while the pointer is on it', (
    tester,
  ) async {
    final item = fixtureItem(id: 'p1', type: ItemType.photo);
    final controller = _controller(FakeItemsRepository(items: [item]));
    addTearDown(controller.dispose);
    final dummy = File('/tmp/unused.jpg');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ItemHoverPreview(
              item: item,
              controller: controller,
              hoverDelay: Duration.zero,
              faces: const [
                HoverPreviewFace(
                  number: 1,
                  region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
                  personName: 'Maya',
                ),
              ],
              resolveMedia: (_) async => LocalMediaResolution(
                status: LocalMediaStatus.available,
                file: dummy,
                path: dummy.path,
              ),
              buildPhoto: (_) => const SizedBox(
                key: Key('item-hover-preview-photo'),
                width: 400,
                height: 300,
              ),
              child: const SizedBox(width: 56, height: 56),
            ),
          ),
        ),
      ),
    );

    final hover = await _hoverThumb(tester, 'p1');
    await tester.pump();
    final card = find.byKey(const Key('item-hover-preview-card'));
    expect(card, findsOneWidget);

    await hover.moveTo(tester.getCenter(card));
    await tester.pump();
    await tester.pump(kHoverPreviewFaceHideDelay);
    expect(card, findsOneWidget);

    await hover.moveTo(const Offset(780, 580));
    await tester.pump();
    await tester.pump(kHoverPreviewHideDelay);
    expect(card, findsOneWidget);
    await tester.pump(kHoverPreviewFaceHideDelay - kHoverPreviewHideDelay);
    expect(card, findsNothing);
  });

  testWidgets('tapping a numbered hover box reports that face', (tester) async {
    final item = fixtureItem(id: 'p1', type: ItemType.photo);
    final controller = _controller(FakeItemsRepository(items: [item]));
    addTearDown(controller.dispose);
    final dummy = File('/tmp/unused.jpg');
    HoverPreviewFace? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ItemHoverPreview(
              item: item,
              controller: controller,
              hoverDelay: Duration.zero,
              faces: const [
                HoverPreviewFace(
                  number: 1,
                  tagId: 'face_1',
                  region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.5, xMax: 0.5),
                ),
              ],
              onFaceTap: (face, _) async {
                tapped = face;
              },
              resolveMedia: (_) async => LocalMediaResolution(
                status: LocalMediaStatus.available,
                file: dummy,
                path: dummy.path,
              ),
              buildPhoto: (_) => const SizedBox(
                key: Key('item-hover-preview-photo'),
                width: 400,
                height: 300,
              ),
              child: const SizedBox(width: 56, height: 56),
            ),
          ),
        ),
      ),
    );

    final hover = await _hoverThumb(tester, 'p1');
    await tester.pump();
    await tester.tap(find.byKey(const Key('hover-face-label-1')));
    await tester.pump();
    expect(tapped?.number, 1);
    expect(tapped?.tagId, 'face_1');
    await hover.moveTo(const Offset(-80, -80));
    await tester.pump(kHoverPreviewFaceHideDelay);
  });

  group('hoverFaceBoxRect', () {
    const size = Size(400, 300);

    test('places a normal region in the frame', () {
      final rect = hoverFaceBoxRect(
        const TagRegion(yMin: 0.1, xMin: 0.2, yMax: 0.5, xMax: 0.6),
        size,
      )!;
      expect(rect, const Rect.fromLTRB(80, 30, 240, 150));
    });

    test('grows a tiny box around its center to the minimum', () {
      final rect = hoverFaceBoxRect(
        const TagRegion(yMin: 0.5, xMin: 0.5, yMax: 0.501, xMax: 0.501),
        size,
      )!;
      expect(rect.width, kHoverFaceMinBox);
      expect(rect.height, kHoverFaceMinBox);
      expect(rect.center.dx, closeTo(200.2, 0.5));
    });

    test('keeps a grown box inside the frame at an edge', () {
      final rect = hoverFaceBoxRect(
        const TagRegion(yMin: 0, xMin: 0.999, yMax: 0.001, xMax: 1),
        size,
      )!;
      expect(rect.right, lessThanOrEqualTo(size.width));
      expect(rect.left, greaterThanOrEqualTo(0));
    });

    test('has no place for an empty or off-frame region', () {
      expect(
        hoverFaceBoxRect(
          const TagRegion(yMin: 0.1, xMin: 0.5, yMax: 0.4, xMax: 0.5),
          size,
        ),
        isNull,
      );
      expect(
        hoverFaceBoxRect(
          const TagRegion(yMin: 0.1, xMin: 1.5, yMax: 0.4, xMax: 1.8),
          size,
        ),
        isNull,
      );
      expect(
        hoverFaceBoxRect(
          TagRegion(yMin: 0.1, xMin: double.nan, yMax: 0.4, xMax: 0.8),
          size,
        ),
        isNull,
      );
    });
  });

  testWidgets('every numbered face has a box with its name on the still', (
    tester,
  ) async {
    final item = fixtureItem(id: 'p1', type: ItemType.photo);
    final controller = _controller(FakeItemsRepository(items: [item]));
    addTearDown(controller.dispose);
    final dir = Directory.systemTemp.createTempSync('face_boxes_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final photo = File('${dir.path}/still.jpg')
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 48)));
    HoverPreviewFace? tapped;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ItemHoverPreview(
              item: item,
              controller: controller,
              hoverDelay: Duration.zero,
              faces: const [
                HoverPreviewFace(
                  number: 1,
                  tagId: 'f1',
                  region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
                  personName: 'Maya',
                ),
                HoverPreviewFace(
                  number: 2,
                  tagId: 'f2',
                  region: TagRegion(yMin: 0.1, xMin: 0.5, yMax: 0.4, xMax: 0.5),
                  personName: 'Sam',
                ),
                HoverPreviewFace(
                  number: 3,
                  tagId: 'f3',
                  region: TagRegion(yMin: 0.1, xMin: 1.5, yMax: 0.4, xMax: 1.8),
                ),
                HoverPreviewFace(
                  number: 4,
                  tagId: 'f4',
                  region: TagRegion(
                    yMin: 0.6,
                    xMin: 0.5,
                    yMax: 0.601,
                    xMax: 0.501,
                  ),
                  personName: 'Margaret Elizabeth',
                ),
              ],
              onFaceTap: (face, _) async => tapped = face,
              resolveMedia: (_) async => LocalMediaResolution(
                status: LocalMediaStatus.available,
                file: photo,
                path: photo.path,
              ),
              child: const SizedBox(width: 56, height: 56),
            ),
          ),
        ),
      ),
    );

    final hover = await _hoverThumb(tester, 'p1');
    for (var i = 0; i < 40; i++) {
      if (find.byKey(const Key('hover-face-label-4')).evaluate().isNotEmpty) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('1 Maya'), findsOneWidget);
    expect(find.text('2 Sam'), findsOneWidget);
    expect(find.text('3 Unassigned'), findsOneWidget);
    // A tiny box still carries the whole name.
    expect(find.text('4 Margaret Elizabeth'), findsOneWidget);
    // Placed boxes sit on the face; the two that cannot be placed are stacked.
    expect(find.byKey(const Key('hover-face-unplaced-1')), findsNothing);
    expect(find.byKey(const Key('hover-face-unplaced-2')), findsOneWidget);
    expect(find.byKey(const Key('hover-face-unplaced-3')), findsOneWidget);
    expect(find.byKey(const Key('hover-face-unplaced-4')), findsNothing);

    await tester.tap(find.byKey(const Key('hover-face-label-3')));
    await tester.pump();
    expect(tapped?.tagId, 'f3');

    await hover.moveTo(const Offset(-80, -80));
    await tester.pump(kHoverPreviewFaceHideDelay);
  });

  group('video face still', () {
    const period = KeyPeriodKnowledge(
      id: 'kp1',
      itemId: 'v1',
      startMs: 2000,
      endMs: 9000,
      sampleTimestampMs: 5000,
      tags: [],
    );
    const faces = [
      HoverPreviewFace(
        number: 1,
        tagId: 'face_1',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.5, xMax: 0.5),
        personName: 'Maya',
      ),
    ];

    Future<void> pumpHover(
      WidgetTester tester, {
      required Item item,
      required LibraryTableController controller,
      required _FakeVideoSession session,
      required Future<File?> Function()? faceStill,
      HoverFaceTap? onFaceTap,
    }) async {
      final dummy = File('/tmp/unused.mp4');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ItemHoverPreview(
                item: item,
                controller: controller,
                period: period,
                hoverDelay: Duration.zero,
                faces: faces,
                onFaceTap: onFaceTap,
                faceStill: faceStill,
                resolveMedia: (_) async => LocalMediaResolution(
                  status: LocalMediaStatus.available,
                  file: dummy,
                  path: dummy.path,
                ),
                openVideo: (_) async => session,
                child: const SizedBox(width: 56, height: 56),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> pumpUntil(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('opens on the still with squares and plays on request', (
      tester,
    ) async {
      final item = fixtureItem(id: 'v1', type: ItemType.video);
      final controller = _controller(FakeItemsRepository(items: [item]));
      addTearDown(controller.dispose);
      final dir = Directory.systemTemp.createTempSync('face_still_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final still = File('${dir.path}/still.jpg')
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 48)));
      final session = _FakeVideoSession();
      HoverPreviewFace? tapped;

      await pumpHover(
        tester,
        item: item,
        controller: controller,
        session: session,
        faceStill: () async => still,
        onFaceTap: (face, _) async => tapped = face,
      );

      final hover = await _hoverThumb(tester, 'v1', periodId: 'kp1');
      await pumpUntil(tester, find.byKey(const Key('hover-play-period')));
      expect(find.byKey(const Key('item-hover-preview-photo')), findsOneWidget);
      expect(find.byKey(const Key('item-hover-preview-video')), findsNothing);
      expect(find.byKey(const Key('hover-play-period')), findsOneWidget);
      expect(session.playCount, 0);

      await tester.tap(find.byKey(const Key('hover-face-label-1')));
      await tester.pump();
      expect(tapped?.tagId, 'face_1');

      await tester.tap(find.byKey(const Key('hover-play-period')));
      await pumpUntil(
        tester,
        find.byKey(const Key('item-hover-preview-video')),
      );
      expect(find.byKey(const Key('item-hover-preview-video')), findsOneWidget);
      expect(find.byKey(const Key('hover-show-still')), findsOneWidget);
      expect(find.byKey(const Key('hover-face-label-1')), findsOneWidget);
      expect(session.playCount, 1);
      expect(session.clips.single.start, const Duration(milliseconds: 2000));
      expect(session.clips.single.stopAt, const Duration(milliseconds: 9000));
      // The still-based preview plays once and offers Show still in the
      // player's own controls (the bar itself stays).
      expect(session.loops, [false]);
      expect(session.showStillOffered.last, isTrue);

      await tester.tap(find.byKey(const Key('hover-show-still')));
      await tester.pump();
      expect(session.disposed, isTrue);
      expect(find.byKey(const Key('item-hover-preview-video')), findsNothing);
      expect(find.byKey(const Key('hover-play-period')), findsOneWidget);
      await hover.moveTo(const Offset(-80, -80));
      await tester.pump(kHoverPreviewFaceHideDelay);
    });

    testWidgets('returns to the still when the segment ends, and replays', (
      tester,
    ) async {
      final item = fixtureItem(id: 'v1', type: ItemType.video);
      final controller = _controller(FakeItemsRepository(items: [item]));
      addTearDown(controller.dispose);
      final dir = Directory.systemTemp.createTempSync('face_still_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final still = File('${dir.path}/still.jpg')
        ..writeAsBytesSync(img.encodeJpg(img.Image(width: 64, height: 48)));
      final session = _FakeVideoSession();

      await pumpHover(
        tester,
        item: item,
        controller: controller,
        session: session,
        faceStill: () async => still,
        onFaceTap: (_, _) async {},
      );

      final hover = await _hoverThumb(tester, 'v1', periodId: 'kp1');
      await pumpUntil(tester, find.byKey(const Key('hover-play-period')));
      await tester.tap(find.byKey(const Key('hover-play-period')));
      await pumpUntil(
        tester,
        find.byKey(const Key('item-hover-preview-video')),
      );
      expect(find.byKey(const Key('item-hover-preview-video')), findsOneWidget);

      session.ended.add(null);
      await tester.pump();
      expect(find.byKey(const Key('item-hover-preview-video')), findsNothing);
      expect(find.byKey(const Key('item-hover-preview-photo')), findsOneWidget);
      expect(find.byKey(const Key('hover-play-period')), findsOneWidget);
      expect(session.disposed, isTrue);

      await tester.tap(find.byKey(const Key('hover-play-period')));
      await pumpUntil(
        tester,
        find.byKey(const Key('item-hover-preview-video')),
      );
      expect(find.byKey(const Key('item-hover-preview-video')), findsOneWidget);
      expect(session.playCount, 2);

      await hover.moveTo(const Offset(-80, -80));
      await tester.pump(kHoverPreviewFaceHideDelay);
    });

    testWidgets('without a still it plays the clip with the name line', (
      tester,
    ) async {
      final item = fixtureItem(id: 'v1', type: ItemType.video);
      final controller = _controller(FakeItemsRepository(items: [item]));
      addTearDown(controller.dispose);
      final session = _FakeVideoSession();

      await pumpHover(
        tester,
        item: item,
        controller: controller,
        session: session,
        faceStill: () async => null,
        onFaceTap: (_, _) async {},
      );

      final hover = await _hoverThumb(tester, 'v1', periodId: 'kp1');
      await pumpUntil(
        tester,
        find.byKey(const Key('item-hover-preview-video')),
      );
      expect(find.byKey(const Key('item-hover-preview-video')), findsOneWidget);
      expect(find.byKey(const Key('hover-play-period')), findsNothing);
      expect(find.byKey(const Key('hover-show-still')), findsNothing);
      expect(session.showStillOffered.last, isFalse);
      expect(session.loops, [true]);
      expect(find.byKey(const Key('hover-face-label-1')), findsOneWidget);
      expect(session.playCount, 1);

      await hover.moveTo(const Offset(-80, -80));
      await tester.pump(kHoverPreviewFaceHideDelay);
    });
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
    expect(session.clips, hasLength(1));
    expect(session.clips.single.start, Duration.zero);
    expect(session.clips.single.stopAt, const Duration(milliseconds: 1800));
    expect(session.calls, ['prepare', 'setClip', 'seek', 'play']);

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
    expect(session.clips.single.stopAt, const Duration(seconds: 4));

    gate.complete();
    await tester.pump();
    await tester.pump();
    expect(session.clips.last.stopAt, const Duration(milliseconds: 1200));
    expect(session.clips.last.start, Duration.zero);
  });

  testWidgets('video hover on a key-period tile plays that span', (
    tester,
  ) async {
    final item = fixtureItem(
      id: 'v3',
      type: ItemType.video,
      processingStatus: ProcessingStatus.tagged,
    );
    const period = KeyPeriodKnowledge(
      id: 'kp-late',
      itemId: 'v3',
      startMs: 2000,
      endMs: 4500,
      tags: [],
    );
    final controller = _controller(FakeItemsRepository(items: [item]));
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
              period: period,
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

    final hover = await _hoverThumb(tester, 'v3', periodId: 'kp-late');
    await tester.pump();
    expect(find.byKey(const Key('item-hover-preview-video')), findsOneWidget);
    expect(session.playCount, 1);
    expect(session.seeks, isNot(contains(Duration.zero)));
    expect(session.seeks, contains(const Duration(milliseconds: 2000)));
    expect(session.clips.single.start, const Duration(milliseconds: 2000));
    expect(session.clips.single.stopAt, const Duration(milliseconds: 4500));
    expect(session.calls, ['prepare', 'setClip', 'seek', 'play']);

    await hover.moveTo(const Offset(-80, -80));
    await tester.pump();
    await tester.pump(kHoverPreviewHideDelay);
    expect(session.disposed, isTrue);
  });

  testWidgets('video hover with one late period starts at that period not 0', (
    tester,
  ) async {
    final item = fixtureItem(
      id: 'v-late',
      type: ItemType.video,
      processingStatus: ProcessingStatus.tagged,
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {
        'v-late': fixtureKnowledge(
          item: item,
          tags: const [],
          keyPeriods: [
            KeyPeriodKnowledge(
              id: 'kp-late',
              itemId: 'v-late',
              startMs: 9583,
              endMs: 42357,
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

    await _hoverThumb(tester, 'v-late');
    await tester.pump();
    expect(session.seeks, isNot(contains(Duration.zero)));
    expect(session.seeks, contains(const Duration(milliseconds: 9583)));
    expect(session.clips.single.start, const Duration(milliseconds: 9583));
    expect(session.clips.single.stopAt, const Duration(milliseconds: 42357));
    expect(session.calls.first, 'prepare');
    expect(session.calls.last, 'play');
  });

  test('hoverAbLoopTimestamp is seconds for mpv ab-loop', () {
    expect(hoverAbLoopTimestamp(Duration.zero), '0');
    expect(
      double.parse(hoverAbLoopTimestamp(const Duration(milliseconds: 9583))),
      closeTo(9.583, 0.000001),
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
