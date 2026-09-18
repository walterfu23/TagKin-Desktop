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

String _sec(double seconds) => seconds.toStringAsFixed(3);

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
    final d = _sec(inputs[i].durationSeconds);
    prepared.add(
      '[$i:v]$scale,fps=$kItemListNleTimebase,format=yuv420p,'
      'trim=duration=$d,setpts=PTS-STARTPTS,'
      'fps=$kItemListNleTimebase[v$i]',
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
    var leftDuration = inputs[0].durationSeconds;
    for (var i = 0; i < inputs.length - 1; i++) {
      final join = xfadeByAfter[i];
      final named = join == null ? '' : itemListMp4XfadeName(join.kind);
      final useXfade = named.isNotEmpty && join != null;
      final overlap = useXfade ? _framesToSeconds(join.durationFrames) : 0.0;
      final offset = leftDuration - overlap;
      final out = i == inputs.length - 2 ? '[vout]' : '[x$i]';
      if (useXfade) {
        hasXfade = true;
        prepared.add(
          '$current[v${i + 1}]'
          'xfade=transition=$named'
          ':duration=${_sec(overlap)}'
          ':offset=${_sec(offset)}$out',
        );
        leftDuration += inputs[i + 1].durationSeconds - overlap;
      } else {
        prepared.add(
          '$current[v${i + 1}]concat=n=2:v=1:a=0$out',
        );
        leftDuration += inputs[i + 1].durationSeconds;
      }
      current = out;
    }
  }

  final total = _framesToSeconds(timeline.duration);
  final fade = audioFadeOutSeconds <= 0
      ? 0.0
      : (audioFadeOutSeconds > total / 2 ? total / 2 : audioFadeOutSeconds);
  final fadeStart = (total - fade).clamp(0.0, total).toDouble();
  prepared.add(
    '[${inputs.length}:a]aresample=44100,'
    'aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo,'
    'atrim=0:${_sec(total)},'
    'afade=t=out:st=${_sec(fadeStart)}:d=${_sec(fade)},'
    'asetpts=PTS-STARTPTS[aout]',
  );

  return ItemListMp4Plan(
    inputs: inputs,
    filterComplex: prepared.join(';'),
    videoDurationSeconds: total,
    hasXfade: hasXfade,
  );
}
