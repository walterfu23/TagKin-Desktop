import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/key_period_offsets.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';

/// Timeline of video [KeyPeriodKnowledge] rows; tap seeks the local player (D8).
class KeyPeriodScrubber extends StatelessWidget {
  const KeyPeriodScrubber({
    super.key,
    required this.keyPeriods,
    this.player,
    this.duration,
    this.onSeek,
  });

  final List<KeyPeriodKnowledge> keyPeriods;

  /// Optional live player — when null, [onSeek] is still invoked for tests.
  final Player? player;

  /// Known media duration (clamps seeks). When null, seeks are unclamped.
  final Duration? duration;

  /// Injectable seek hook (unit/widget tests without media_kit).
  final void Function(Duration seek)? onSeek;

  void _seekTo(int startMs) {
    var seek = keyPeriodMsToSeek(startMs);
    final d = duration;
    if (d != null) {
      seek = clampSeekToDuration(seek, d);
    }
    onSeek?.call(seek);
    player?.seek(seek);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('key-period-scrubber'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Key periods',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (keyPeriods.isEmpty)
          const Text(
            'No key periods yet.',
            key: Key('key-periods-empty'),
          )
        else
          for (final period in keyPeriods)
            _KeyPeriodTile(
              period: period,
              onTap: () => _seekTo(period.startMs),
            ),
      ],
    );
  }
}

class _KeyPeriodTile extends StatelessWidget {
  const _KeyPeriodTile({
    required this.period,
    required this.onTap,
  });

  final KeyPeriodKnowledge period;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final start = _formatMs(period.startMs);
    final end = _formatMs(period.endMs);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        key: Key('key-period-${period.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Key period $start – $end',
                key: Key('key-period-range-${period.id}'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (period.tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final tag in period.tags)
                  Text(
                    '${tag.dimension}: ${tag.value} (${provenanceLabel(tag)})',
                    key: Key('key-period-tag-${tag.id}'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _formatMs(int ms) {
  final d = Duration(milliseconds: ms);
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  final frac = (d.inMilliseconds.remainder(1000) ~/ 10)
      .toString()
      .padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:$m:$s.$frac';
  }
  return '$m:$s.$frac';
}
