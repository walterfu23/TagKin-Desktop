import 'package:tagkin_desktop/item_lists/item_list_nle.dart';

/// ffmpeg `xfade` name for a photo-to-photo transition. Empty when None.
String itemListMp4XfadeName(ExportPhotoTransition transition) {
  return switch (transition) {
    ExportPhotoTransition.none => '',
    ExportPhotoTransition.crossDissolve => 'fade',
    ExportPhotoTransition.dipToBlack => 'fadeblack',
    ExportPhotoTransition.dipToWhite => 'fadewhite',
  };
}

class ItemListMp4Input {
  const ItemListMp4Input({
    required this.path,
    required this.isStill,
    required this.sourceStartSeconds,
    required this.durationSeconds,
  });

  final String path;
  final bool isStill;
  final double sourceStartSeconds;
  final double durationSeconds;
}

class ItemListMp4Plan {
  const ItemListMp4Plan({
    required this.inputs,
    required this.filterComplex,
    required this.videoDurationSeconds,
    required this.hasXfade,
  });

  final List<ItemListMp4Input> inputs;
  final String filterComplex;
  final double videoDurationSeconds;
  final bool hasXfade;
}

double _framesToSeconds(int frames) => frames / kItemListNleTimebase;

/// Build an ffmpeg filter_complex from the NLE timeline (no process spawn).
ItemListMp4Plan itemListMp4Plan({
  required ItemListNleTimeline timeline,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
  double audioFadeOutSeconds = 2,
}) {
  if (timeline.clips.isEmpty) {
    throw StateError('Cannot render an empty item list');
  }
  final inputs = <ItemListMp4Input>[];
  for (final clip in timeline.clips) {
    final path = clip.localPath;
    if (path == null || path.isEmpty) {
      throw StateError('Missing local file for a clip');
    }
    inputs.add(
      ItemListMp4Input(
        path: path,
        isStill: clip.isStill,
        sourceStartSeconds: _framesToSeconds(clip.sourceIn),
        durationSeconds: _framesToSeconds(clip.timelineDuration),
      ),
    );
  }

  final w = sequenceWidth < 2 ? 2 : sequenceWidth - (sequenceWidth % 2);
  final h = sequenceHeight < 2 ? 2 : sequenceHeight - (sequenceHeight % 2);
  final scale = scaleToFit
      ? 'scale=$w:$h:force_original_aspect_ratio=decrease,'
          'pad=$w:$h:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1'
      : 'scale=$w:$h:force_original_aspect_ratio=increase,'
          'crop=$w:$h,setsar=1';

  final prepared = <String>[];
  for (var i = 0; i < inputs.length; i++) {
    final d = inputs[i].durationSeconds.toStringAsFixed(3);
    prepared.add(
      '[$i:v]$scale,fps=$kItemListNleTimebase,format=yuv420p,'
      'trim=duration=$d,setpts=PTS-STARTPTS[v$i]',
    );
  }

  var hasXfade = false;
  if (inputs.length == 1) {
    prepared.add('[v0]copy[vout]');
  } else {
    final xfadeByAfter = {
      for (final t in timeline.transitions) t.afterClipIndex: t,
    };
    var current = '[v0]';
    for (var i = 0; i < inputs.length - 1; i++) {
      final join = xfadeByAfter[i];
      final named = join == null
          ? ''
          : itemListMp4XfadeName(join.kind);
      final useXfade = named.isNotEmpty && join != null;
      if (useXfade) hasXfade = true;
      final transition = useXfade ? named : 'fade';
      final duration = useXfade
          ? _framesToSeconds(join.durationFrames)
          : (1 / kItemListNleTimebase);
      final offset = useXfade
          ? _framesToSeconds(join.timelineStart)
          : _framesToSeconds(timeline.clips[i + 1].timelineStart);
      final out = i == inputs.length - 2 ? '[vout]' : '[x$i]';
      prepared.add(
        '$current[v${i + 1}]'
        'xfade=transition=$transition'
        ':duration=${duration.toStringAsFixed(3)}'
        ':offset=${offset.toStringAsFixed(3)}$out',
      );
      current = out;
    }
  }

  final total = _framesToSeconds(timeline.duration);
  final fade = audioFadeOutSeconds <= 0
      ? 0.0
      : (audioFadeOutSeconds > total / 2 ? total / 2 : audioFadeOutSeconds);
  final fadeStart = (total - fade).clamp(0, total);
  prepared.add(
    '[${inputs.length}:a]atrim=0:${total.toStringAsFixed(3)},'
    'afade=t=out:st=${fadeStart.toStringAsFixed(3)}:d=${fade.toStringAsFixed(3)},'
    'asetpts=PTS-STARTPTS[aout]',
  );

  return ItemListMp4Plan(
    inputs: inputs,
    filterComplex: prepared.join(';'),
    videoDurationSeconds: total,
    hasXfade: hasXfade,
  );
}
