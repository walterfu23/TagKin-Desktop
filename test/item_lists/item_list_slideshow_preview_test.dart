import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/item_lists/item_list_slideshow_preview.dart';

import '../fake_items_repository.dart';

class _FakePreviewPlayer implements ItemListPreviewPlayer {
  _FakePreviewPlayer({this.hasVideo = false});

  final bool hasVideo;
  @override
  Duration position = Duration.zero;
  @override
  Duration duration = Duration.zero;
  final opened = <String>[];
  final seeks = <Duration>[];
  final volumes = <double>[];
  int plays = 0;
  int pauses = 0;

  @override
  Widget? get video =>
      hasVideo ? const SizedBox(key: Key('item-list-preview-video')) : null;

  @override
  Future<void> openFile(String path) async {
    opened.add(path);
  }

  @override
  Future<void> play() async {
    plays += 1;
  }

  @override
  Future<void> pause() async {
    pauses += 1;
  }

  @override
  Future<void> seek(Duration to) async {
    seeks.add(to);
    position = to;
  }

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
  }

  @override
  Future<void> dispose() async {}
}

ItemListNleTimeline _timeline() {
  final photo = fixtureItem(
    id: 'still',
    sourceRef: 'file:///tmp/tagkin-preview-still.jpg',
  );
  final video = fixtureItem(
    id: 'clip',
    type: ItemType.video,
    sourceRef: 'file:///tmp/tagkin-preview-clip.mp4',
  );
  return itemListNleTimeline(
    entries: [
      ItemListEntry(
        kind: ItemListEntryKind.photo,
        itemId: photo.id,
        who: const [],
        what: const [],
        where: const [],
      ),
      ItemListEntry(
        kind: ItemListEntryKind.keyperiod,
        itemId: video.id,
        keyPeriodId: 'kp',
        startMs: 4000,
        endMs: 7000,
        who: const [],
        what: const [],
        where: const [],
      ),
    ],
    itemsById: {photo.id: photo, video.id: video},
  );
}

void main() {
  test('soundtrack stays full on stills and ducks on a key period', () {
    expect(
      itemListPreviewSoundtrackVolume(keyPeriod: false, soundtrackDuck: 0.05),
      100,
    );
    expect(
      itemListPreviewSoundtrackVolume(keyPeriod: true, soundtrackDuck: 0.05),
      5,
    );
  });

  test('key period seek starts at startMs plus time into the clip', () {
    final clip = _timeline().clips[1];
    expect(
      itemListPreviewSeek(
        clip: clip,
        soundtrackPosition: const Duration(milliseconds: 3000),
      ),
      const Duration(milliseconds: 4500),
    );
    expect(
      itemListPreviewSeek(
        clip: clip,
        soundtrackPosition: const Duration(milliseconds: 20000),
      ),
      const Duration(milliseconds: 7000),
    );
  });

  testWidgets('play preview opens the key period and ducks the soundtrack', (
    tester,
  ) async {
    final timeline = _timeline();
    final audio = _FakePreviewPlayer();
    final video = _FakePreviewPlayer(hasVideo: true);
    final clip = timeline.clips[1];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemListSlideshowPreview(
            timeline: timeline,
            audioPath: '/tmp/tagkin-preview-music.wav',
            soundtrackDuck: 0.05,
            playerFactory: () => audio,
            videoPlayerFactory: () => video,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('item-list-music-preview-play')));
    await tester.pump();
    await tester.pump();

    expect(audio.opened, ['/tmp/tagkin-preview-music.wav']);
    expect(audio.volumes, [100]);
    expect(video.opened, isEmpty);
    expect(find.byKey(const Key('item-list-preview-video')), findsNothing);

    audio.position = const Duration(milliseconds: 3000);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(video.opened, [clip.localPath]);
    expect(video.seeks, [const Duration(milliseconds: 4500)]);
    expect(video.plays, 1);
    expect(audio.volumes.last, 5);
    expect(find.byKey(const Key('item-list-preview-video')), findsOneWidget);
    expect(find.textContaining('Key period'), findsNothing);

    await tester.tap(find.byKey(const Key('item-list-music-preview-play')));
    await tester.pump();

    expect(audio.pauses, 1);
    expect(video.pauses, 1);

    await tester.tap(find.byKey(const Key('item-list-music-preview-play')));
    await tester.pump();
    await tester.pump();

    expect(audio.opened, ['/tmp/tagkin-preview-music.wav']);
    expect(find.byKey(const Key('item-list-preview-video')), findsOneWidget);
  });

  test('preview clock and clip index follow the timeline', () {
    expect(itemListPreviewClock(Duration.zero), '0:00');
    expect(itemListPreviewClock(const Duration(milliseconds: 3000)), '0:03');
    expect(itemListPreviewClock(const Duration(seconds: 65)), '1:05');
    expect(itemListPreviewClock(const Duration(seconds: 3661)), '1:01:01');

    final clips = _timeline().clips;
    expect(itemListPreviewClipIndex(clips: clips, position: Duration.zero), 0);
    expect(
      itemListPreviewClipIndex(
        clips: clips,
        position: const Duration(milliseconds: 3000),
      ),
      1,
    );
    expect(
      itemListPreviewAudioSeek(
        position: const Duration(milliseconds: 3000),
        audioDuration: const Duration(milliseconds: 1000),
      ),
      const Duration(milliseconds: 1000),
    );
    expect(
      itemListPreviewAudioSeek(
        position: const Duration(milliseconds: 500),
        audioDuration: Duration.zero,
      ),
      const Duration(milliseconds: 500),
    );
  });

  test('end fade opacity ramps across the white tail', () {
    const fade = ItemListNleEndFade(startFrame: 90, durationFrames: 90);
    expect(itemListPreviewInEndFade(frame: 89, endFade: fade), isFalse);
    expect(itemListPreviewEndFadeOpacity(frame: 89, endFade: fade), 0);
    expect(itemListPreviewEndFadeOpacity(frame: 90, endFade: fade), 0);
    expect(
      itemListPreviewEndFadeOpacity(frame: 135, endFade: fade),
      closeTo(0.5, 0.001),
    );
    expect(itemListPreviewEndFadeOpacity(frame: 180, endFade: fade), 1);
  });

  testWidgets('preview holds the last clip under a white ramp', (tester) async {
    final timeline = itemListNleTimeline(
      entries: [
        ItemListEntry(
          kind: ItemListEntryKind.photo,
          itemId: 'still',
          who: const [],
          what: const [],
          where: const [],
        ),
      ],
      itemsById: {
        'still': fixtureItem(
          id: 'still',
          sourceRef: 'file:///tmp/tagkin-preview-still.jpg',
        ),
      },
      stillDurationSeconds: 1,
      endFadeSeconds: kItemListNleEndFadeSeconds,
    );
    final audio = _FakePreviewPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemListSlideshowPreview(
            timeline: timeline,
            audioPath: '/tmp/tagkin-preview-music.wav',
            playerFactory: () => audio,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('item-list-music-preview-play')));
    await tester.pump();
    audio.position = const Duration(milliseconds: 2500);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(find.byKey(const Key('item-list-preview-end-fade')), findsOneWidget);
  });

  Future<void> scrubTo(WidgetTester tester, int ms) async {
    final slider = tester.widget<Slider>(
      find.byKey(const Key('item-list-preview-scrub')),
    );
    slider.onChangeStart!(0);
    slider.onChanged!(ms.toDouble());
    slider.onChangeEnd!(ms.toDouble());
    await tester.pump();
    await tester.pump();
  }

  testWidgets('scrub bar seeks that point and play continues from it', (
    tester,
  ) async {
    final timeline = _timeline();
    final audio = _FakePreviewPlayer();
    final video = _FakePreviewPlayer(hasVideo: true);
    final clip = timeline.clips[1];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemListSlideshowPreview(
            timeline: timeline,
            audioPath: '/tmp/tagkin-preview-music.wav',
            soundtrackDuck: 0.05,
            playerFactory: () => audio,
            videoPlayerFactory: () => video,
          ),
        ),
      ),
    );

    expect(find.text('0:00 / 0:05'), findsOneWidget);

    await scrubTo(tester, 3000);

    expect(audio.opened, ['/tmp/tagkin-preview-music.wav']);
    expect(audio.seeks, [const Duration(milliseconds: 3000)]);
    expect(audio.plays, 0);
    expect(video.opened, [clip.localPath]);
    expect(video.seeks, [const Duration(milliseconds: 4500)]);
    expect(video.plays, 0);
    expect(find.byKey(const Key('item-list-preview-video')), findsOneWidget);
    expect(find.text('0:03 / 0:05'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-music-preview-play')));
    await tester.pump();
    await tester.pump();

    expect(audio.opened, ['/tmp/tagkin-preview-music.wav']);
    expect(audio.plays, 1);
    expect(video.plays, 1);
    expect(find.byKey(const Key('item-list-preview-video')), findsOneWidget);
  });

  testWidgets('scrubbing while playing resumes from the new point', (
    tester,
  ) async {
    final timeline = _timeline();
    final audio = _FakePreviewPlayer();
    final video = _FakePreviewPlayer(hasVideo: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemListSlideshowPreview(
            timeline: timeline,
            audioPath: '/tmp/tagkin-preview-music.wav',
            playerFactory: () => audio,
            videoPlayerFactory: () => video,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('item-list-music-preview-play')));
    await tester.pump();
    await tester.pump();

    await scrubTo(tester, 3000);

    expect(audio.plays, 2);
    expect(audio.seeks, contains(const Duration(milliseconds: 3000)));
    expect(video.plays, greaterThan(0));
    expect(find.text('Pause preview'), findsOneWidget);
    expect(find.byKey(const Key('item-list-preview-video')), findsOneWidget);
  });

  testWidgets('scrub into the white ending shows the ramp', (tester) async {
    final timeline = itemListNleTimeline(
      entries: [
        ItemListEntry(
          kind: ItemListEntryKind.photo,
          itemId: 'still',
          who: const [],
          what: const [],
          where: const [],
        ),
      ],
      itemsById: {
        'still': fixtureItem(
          id: 'still',
          sourceRef: 'file:///tmp/tagkin-preview-still.jpg',
        ),
      },
      stillDurationSeconds: 1,
      endFadeSeconds: kItemListNleEndFadeSeconds,
    );
    final audio = _FakePreviewPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemListSlideshowPreview(
            timeline: timeline,
            audioPath: '/tmp/tagkin-preview-music.wav',
            playerFactory: () => audio,
          ),
        ),
      ),
    );

    await scrubTo(tester, 2500);

    expect(audio.seeks, [const Duration(milliseconds: 2500)]);
    expect(find.byKey(const Key('item-list-preview-end-fade')), findsOneWidget);
    expect(find.text('0:02 / 0:04'), findsOneWidget);
  });

  testWidgets('a short soundtrack seek stays at the file end', (tester) async {
    final timeline = _timeline();
    final audio = _FakePreviewPlayer()
      ..duration = const Duration(milliseconds: 1000);
    final video = _FakePreviewPlayer(hasVideo: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ItemListSlideshowPreview(
            timeline: timeline,
            audioPath: '/tmp/tagkin-preview-music.wav',
            playerFactory: () => audio,
            videoPlayerFactory: () => video,
          ),
        ),
      ),
    );

    await scrubTo(tester, 3000);

    expect(audio.seeks, [const Duration(milliseconds: 1000)]);
    expect(video.seeks, [const Duration(milliseconds: 4500)]);
    expect(find.text('0:03 / 0:05'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-music-preview-play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.text('0:03 / 0:05'), findsOneWidget);
    expect(find.byKey(const Key('item-list-preview-video')), findsOneWidget);
  });
}
