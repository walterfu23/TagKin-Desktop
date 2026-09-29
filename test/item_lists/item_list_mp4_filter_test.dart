import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart'
    hide ItemListExportFormat;
import 'package:tagkin_desktop/item_lists/item_list_mp4_filter.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_materialize.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

void main() {
  test('itemListMp4XfadeName maps photo transitions', () {
    expect(itemListMp4XfadeName(ExportPhotoTransition.none), '');
    expect(itemListMp4XfadeName(ExportPhotoTransition.crossDissolve), 'fade');
    expect(itemListMp4XfadeName(ExportPhotoTransition.dipToBlack), 'fadeblack');
    expect(itemListMp4XfadeName(ExportPhotoTransition.dipToWhite), 'fadewhite');
  });

  test('itemListMp4Plan builds xfade + audio fade from the NLE timeline', () {
    final timeline = itemListNleTimeline(
      entries: [
        fixtureEntry(itemId: 'p1'),
        fixtureEntry(itemId: 'p2'),
      ],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg'),
        'p2': fixtureItem(id: 'p2', sourceRef: 'file:///b.jpg'),
      },
    );
    final plan = itemListMp4Plan(
      timeline: timeline,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    expect(plan.inputs, hasLength(2));
    expect(plan.hasXfade, isTrue);
    expect(plan.filterComplex, contains('trim=duration=2.500'));
    expect(
      plan.filterComplex,
      contains('setpts=PTS-STARTPTS,fps=$kItemListNleTimebase'),
    );
    expect(plan.filterComplex, isNot(contains('loop=loop=-1')));
    expect(plan.filterComplex, contains('xfade=transition=fade'));
    expect(plan.filterComplex, contains(':offset=1.500'));
    expect(plan.filterComplex, isNot(contains('concat=')));
    expect(plan.filterComplex, contains('[aout]'));
    expect(plan.filterComplex, contains('[vout]'));
    expect(plan.filterComplex, isNot(contains('volume=')));
    expect(plan.filterComplex, isNot(contains('[0:a]')));
    expect(
      plan.filterComplex,
      contains(
        'aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo',
      ),
    );
    expect(plan.videoDurationSeconds, greaterThan(0));
    expect(
      itemListNleTimelineDurationMs(timeline),
      (timeline.duration * 1000 / kItemListNleTimebase).round(),
    );
  });

  test('hard-cut photos concat instead of xfade', () {
    final timeline = itemListNleTimeline(
      entries: [
        fixtureEntry(itemId: 'p1'),
        fixtureEntry(itemId: 'p2'),
      ],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg'),
        'p2': fixtureItem(id: 'p2', sourceRef: 'file:///b.jpg'),
      },
      transition: ExportPhotoTransition.none,
    );
    final plan = itemListMp4Plan(
      timeline: timeline,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    expect(plan.hasXfade, isFalse);
    expect(plan.filterComplex, contains('concat=n=2:v=1:a=0'));
    expect(
      plan.filterComplex,
      contains(
        'concat=n=2:v=1:a=0,fps=$kItemListNleTimebase,settb=1/$kItemListNleTimebase',
      ),
    );
    expect(plan.filterComplex, isNot(contains('xfade=')));
  });

  test('hard cut then dissolve keeps the sequence timebase', () {
    final timeline = itemListNleTimeline(
      entries: [
        fixtureEntry(itemId: 'p1'),
        fixtureEntry(itemId: 'p2'),
        fixtureEntry(
          itemId: 'v1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp1',
          startMs: 0,
          endMs: 1000,
        ),
        fixtureEntry(itemId: 'p3'),
        fixtureEntry(itemId: 'p4'),
      ],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg'),
        'p2': fixtureItem(id: 'p2', sourceRef: 'file:///b.jpg'),
        'v1': fixtureItem(
          id: 'v1',
          type: ItemType.video,
          sourceRef: 'file:///c.mp4',
        ),
        'p3': fixtureItem(id: 'p3', sourceRef: 'file:///d.jpg'),
        'p4': fixtureItem(id: 'p4', sourceRef: 'file:///e.jpg'),
      },
    );
    final plan = itemListMp4Plan(
      timeline: timeline,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    const normalized =
        'concat=n=2:v=1:a=0,fps=$kItemListNleTimebase,settb=1/$kItemListNleTimebase';
    expect(plan.hasXfade, isTrue);
    expect(normalized.allMatches(plan.filterComplex).length, 2);
    expect(plan.filterComplex, contains('xfade=transition=fade'));
  });

  test('MP4 format is a local media export, not a vendor name', () {
    expect(ItemListExportFormat.mp4WithMusic.label, 'MP4 (with music)');
    expect(ItemListExportFormat.mp4WithMusic.fileExtension, 'mp4');
    expect(ItemListExportFormat.mp4.label, 'MP4 (without music)');
    expect(ItemListExportFormat.mp4.fileExtension, 'mp4');
  });

  test('clip encode holds a still with -t; assemble maps clip mp4s', () {
    const still = ItemListMp4Input(
      path: '/tmp/a.jpg',
      isStill: true,
      sourceStartSeconds: 0,
      durationSeconds: 2.5,
    );
    final clipArgs = itemListMp4ClipEncodeArgs(
      input: still,
      outputPath: '/tmp/clip-0.mp4',
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    expect(clipArgs, containsAllInOrder(['-framerate', '30', '-loop', '1']));
    expect(clipArgs, containsAllInOrder(['-t', '2.500']));
    expect(clipArgs, containsAllInOrder(['-r', '30']));
    expect(clipArgs, containsAllInOrder(['-c:v', 'libx264']));
    expect(clipArgs, containsAllInOrder(['-preset', 'ultrafast']));
    expect(clipArgs, contains('-an'));
    expect(clipArgs.last, '/tmp/clip-0.mp4');

    final timeline = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg')},
    );
    final assembled = itemListMp4TimelineWithClipVideos(timeline, [
      '/tmp/clip-0.mp4',
    ]);
    final plan = itemListMp4Plan(
      timeline: assembled,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    final args = itemListMp4AssembleArgs(
      plan: plan,
      audioPath: '/tmp/music.wav',
      outputPath: '/tmp/out.mp4',
    );
    expect(args, containsAllInOrder(['-i', '/tmp/clip-0.mp4']));
    expect(args, isNot(contains('-loop')));
    expect(args, isNot(contains('-stream_loop')));
    expect(plan.filterComplex, contains('apad'));
    expect(args, containsAllInOrder(['-c:v', 'libx264']));
    expect(args, containsAllInOrder(['-preset', 'veryfast']));
    expect(args, containsAllInOrder(['-movflags', '+faststart']));
    expect(args, containsAllInOrder(['-tag:v', 'avc1']));
    expect(args, containsAllInOrder(['-profile:v', 'high']));
    expect(args, containsAllInOrder(['-pix_fmt', 'yuv420p']));
    expect(args, containsAllInOrder(['-profile:a', 'aac_low']));
    expect(args, containsAllInOrder(['-ar', '44100']));
    expect(args, containsAllInOrder(['-ac', '2']));
    expect(args, containsAllInOrder(['-t', '2.500']));
    expect(args, isNot(contains('-shortest')));
    expect(args.last, '/tmp/out.mp4');
    expect(assembled.clips.single.isStill, isTrue);
  });

  test('key-period clip keeps AAC; silent source gets anullsrc', () {
    const video = ItemListMp4Input(
      path: '/tmp/clip.mp4',
      isStill: false,
      sourceStartSeconds: 1,
      durationSeconds: 3,
      timelineStartSeconds: 2.5,
    );
    final withAudio = itemListMp4ClipEncodeArgs(
      input: video,
      outputPath: '/tmp/clip-0.mp4',
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
      hasAudio: true,
    );
    expect(withAudio, isNot(contains('-an')));
    expect(withAudio, isNot(contains('anullsrc=r=44100:cl=stereo')));
    expect(withAudio, containsAllInOrder(['-ss', '1.000', '-t', '3.000']));
    expect(withAudio, containsAllInOrder(['-c:a', 'aac']));
    expect(withAudio, containsAllInOrder(['-profile:a', 'aac_low']));

    final silent = itemListMp4ClipEncodeArgs(
      input: video,
      outputPath: '/tmp/clip-0.mp4',
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    expect(silent, contains('anullsrc=r=44100:cl=stereo'));
    expect(silent, containsAllInOrder(['-map', '0:v:0', '-map', '1:a:0']));
    expect(silent, containsAllInOrder(['-c:a', 'aac']));
    expect(silent, isNot(contains('-an')));
  });

  test('key-period audio is mixed full; soundtrack ducks under it', () {
    final timeline = itemListNleTimeline(
      entries: [
        fixtureEntry(itemId: 'p1'),
        fixtureEntry(
          itemId: 'v1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp-1',
          startMs: 1000,
          endMs: 4000,
        ),
      ],
      itemsById: {
        'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg'),
        'v1': fixtureItem(
          id: 'v1',
          type: ItemType.video,
          sourceRef: 'file:///clip.mp4',
        ),
      },
    );
    final assembled = itemListMp4TimelineWithClipVideos(timeline, [
      '/tmp/clip-0.mp4',
      '/tmp/clip-1.mp4',
    ]);
    expect(assembled.clips[0].isStill, isTrue);
    expect(assembled.clips[1].isStill, isFalse);

    final plan = itemListMp4Plan(
      timeline: assembled,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    expect(plan.inputs[1].timelineStartSeconds, 2.5);
    expect(
      plan.filterComplex,
      contains(
        'volume=${kItemListMp4SoundtrackDuckDefault.toStringAsFixed(3)}:'
        "enable='between(t,2.500,5.500)'",
      ),
    );
    expect(plan.filterComplex, contains('[1:a]'));
    expect(plan.filterComplex, contains('adelay=2500|2500:all=1[ca1]'));
    expect(
      plan.filterComplex,
      contains('amix=inputs=2:duration=first:dropout_transition=0:normalize=0'),
    );
    expect(plan.filterComplex, contains('[aout]'));
    expect(plan.filterComplex, isNot(contains('[0:a]')));

    final louder = itemListMp4Plan(
      timeline: assembled,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
      soundtrackDuck: 0.25,
    );
    expect(
      louder.filterComplex,
      contains("volume=0.250:enable='between(t,2.500,5.500)'"),
    );
  });

  test('videotoolbox clip/assemble args use bitrate, not a preset', () {
    const still = ItemListMp4Input(
      path: '/tmp/a.jpg',
      isStill: true,
      sourceStartSeconds: 0,
      durationSeconds: 2.5,
    );
    final clipArgs = itemListMp4ClipEncodeArgs(
      input: still,
      outputPath: '/tmp/clip-0.mp4',
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
      encoder: ItemListMp4EncoderKind.videotoolbox,
    );
    expect(clipArgs, containsAllInOrder(['-c:v', 'h264_videotoolbox']));
    expect(clipArgs, containsAllInOrder(['-allow_sw', '0']));
    expect(clipArgs, containsAllInOrder(['-realtime', '0']));
    expect(clipArgs, containsAllInOrder(['-b:v', '8M']));
    expect(clipArgs, containsAllInOrder(['-maxrate', '8M']));
    expect(clipArgs, containsAllInOrder(['-bufsize', '16M']));
    expect(clipArgs, isNot(contains('-preset')));

    final timeline = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg')},
    );
    final assembled = itemListMp4TimelineWithClipVideos(timeline, [
      '/tmp/clip-0.mp4',
    ]);
    final plan = itemListMp4Plan(
      timeline: assembled,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    final args = itemListMp4AssembleArgs(
      plan: plan,
      audioPath: '/tmp/music.wav',
      outputPath: '/tmp/out.mp4',
      encoder: ItemListMp4EncoderKind.videotoolbox,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
    );
    expect(args, containsAllInOrder(['-c:v', 'h264_videotoolbox']));
    expect(args, containsAllInOrder(['-b:v', '8M']));
    expect(args, isNot(contains('-preset')));
  });

  test('mediaFoundation clip args use bitrate and no VideoToolbox flags', () {
    const still = ItemListMp4Input(
      path: '/tmp/a.jpg',
      isStill: true,
      sourceStartSeconds: 0,
      durationSeconds: 2.5,
    );
    final clipArgs = itemListMp4ClipEncodeArgs(
      input: still,
      outputPath: '/tmp/clip-0.mp4',
      sequenceWidth: 1280,
      sequenceHeight: 720,
      scaleToFit: true,
      encoder: ItemListMp4EncoderKind.mediaFoundation,
    );
    expect(clipArgs, containsAllInOrder(['-c:v', 'h264_mf']));
    expect(clipArgs, containsAllInOrder(['-b:v', '4M']));
    expect(clipArgs, containsAllInOrder(['-bufsize', '8M']));
    expect(clipArgs, isNot(contains('-allow_sw')));
    expect(clipArgs, isNot(contains('-preset')));
  });

  test('end fade holds the last frame and dissolves to white', () {
    final timeline = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg')},
      endFadeSeconds: kItemListNleEndFadeSeconds,
    );
    final plan = itemListMp4Plan(
      timeline: timeline,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
    );
    expect(plan.hasXfade, isTrue);
    expect(plan.videoDurationSeconds, closeTo(5.5, 0.001));
    expect(plan.filterComplex, contains('[v0]copy[vbody]'));
    expect(
      plan.filterComplex,
      contains('tpad=stop_mode=clone:stop_duration=3.000'),
    );
    expect(plan.filterComplex, contains('color=c=white:s=1920x1080'));
    expect(
      plan.filterComplex,
      contains('xfade=transition=fade:duration=3.000:offset=2.500[vout]'),
    );
  });

  test('no soundtrack mixes silence and keeps key-period audio', () {
    final stills = itemListNleTimeline(
      entries: [fixtureEntry(itemId: 'p1')],
      itemsById: {'p1': fixtureItem(id: 'p1', sourceRef: 'file:///a.jpg')},
    );
    final stillPlan = itemListMp4Plan(
      timeline: stills,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
      includeSoundtrack: false,
    );
    expect(stillPlan.filterComplex, contains('anullsrc=r=44100:cl=stereo'));
    expect(stillPlan.filterComplex, isNot(contains('[1:a]')));

    final mixed = itemListNleTimeline(
      entries: [
        fixtureEntry(
          itemId: 'v1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp1',
          startMs: 0,
          endMs: 1000,
        ),
      ],
      itemsById: {
        'v1': fixtureItem(
          id: 'v1',
          type: ItemType.video,
          sourceRef: 'file:///c.mp4',
        ),
      },
    );
    final mixedPlan = itemListMp4Plan(
      timeline: mixed,
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      scaleToFit: true,
      includeSoundtrack: false,
    );
    expect(mixedPlan.filterComplex, contains('anullsrc=r=44100:cl=stereo'));
    expect(mixedPlan.filterComplex, contains('[0:a]'));
    expect(mixedPlan.filterComplex, isNot(contains('[1:a]')));
    final args = itemListMp4AssembleArgs(
      plan: mixedPlan,
      audioPath: null,
      outputPath: '/tmp/out.mp4',
    );
    expect(args, containsAllInOrder(['-i', mixedPlan.inputs.single.path]));
    expect(args.where((arg) => arg == '-i'), hasLength(1));
  });
}
