import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/knowledge/comments_view.dart';
import 'package:tagkin_desktop/review/key_period_offsets.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';

/// Timeline of video [KeyPeriodKnowledge] rows; tap seeks the local player (D8).
///
/// Optional D10 controls: edit bounds, key-period comments.
class KeyPeriodScrubber extends StatelessWidget {
  const KeyPeriodScrubber({
    super.key,
    required this.keyPeriods,
    this.player,
    this.duration,
    this.onSeek,
    this.onEditBounds,
    this.commentsFor,
    this.onAddComment,
    this.onEditComment,
    this.onDeleteComment,
    this.correctionsEnabled = true,
  });

  final List<KeyPeriodKnowledge> keyPeriods;

  /// Optional live player — when null, [onSeek] is still invoked for tests.
  final Player? player;

  /// Known media duration (clamps seeks). When null, seeks are unclamped.
  final Duration? duration;

  /// Injectable seek hook (unit/widget tests without media_kit).
  final void Function(Duration seek)? onSeek;

  /// Edit key-period start/end (D10).
  final void Function(KeyPeriodKnowledge period)? onEditBounds;

  /// Comments scoped to a key period (D10).
  final List<Comment> Function(String keyPeriodId)? commentsFor;

  final Future<void> Function(String keyPeriodId, String body)? onAddComment;
  final Future<void> Function(String commentId, String body)? onEditComment;
  final Future<void> Function(String commentId)? onDeleteComment;
  final bool correctionsEnabled;

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
              onEditBounds: onEditBounds,
              comments: commentsFor?.call(period.id) ?? const [],
              onAddComment: onAddComment == null
                  ? null
                  : (body) => onAddComment!(period.id, body),
              onEditComment: onEditComment,
              onDeleteComment: onDeleteComment,
              enabled: correctionsEnabled,
            ),
      ],
    );
  }
}

class _KeyPeriodTile extends StatefulWidget {
  const _KeyPeriodTile({
    required this.period,
    required this.onTap,
    this.onEditBounds,
    this.comments = const [],
    this.onAddComment,
    this.onEditComment,
    this.onDeleteComment,
    this.enabled = true,
  });

  final KeyPeriodKnowledge period;
  final VoidCallback onTap;
  final void Function(KeyPeriodKnowledge period)? onEditBounds;
  final List<Comment> comments;
  final Future<void> Function(String body)? onAddComment;
  final Future<void> Function(String commentId, String body)? onEditComment;
  final Future<void> Function(String commentId)? onDeleteComment;
  final bool enabled;

  @override
  State<_KeyPeriodTile> createState() => _KeyPeriodTileState();
}

class _KeyPeriodTileState extends State<_KeyPeriodTile> {
  bool _commentsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final period = widget.period;
    final start = _formatMs(period.startMs);
    final end = _formatMs(period.endMs);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: Key('key-period-${period.id}'),
              onTap: widget.onTap,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Key period $start – $end',
                      key: Key('key-period-range-${period.id}'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (widget.onEditBounds != null)
                    IconButton(
                      key: Key('key-period-edit-bounds-${period.id}'),
                      tooltip: 'Edit bounds',
                      iconSize: 18,
                      onPressed: widget.enabled
                          ? () => widget.onEditBounds!(period)
                          : null,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                ],
              ),
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
            if (widget.onAddComment != null || widget.comments.isNotEmpty) ...[
              const SizedBox(height: 4),
              TextButton(
                key: Key('key-period-comments-toggle-${period.id}'),
                onPressed: () =>
                    setState(() => _commentsExpanded = !_commentsExpanded),
                child: Text(
                  _commentsExpanded
                      ? 'Hide comments'
                      : 'Comments (${widget.comments.length})',
                ),
              ),
              if (_commentsExpanded)
                CommentsView(
                  listKey: Key('key-period-comments-${period.id}'),
                  title: 'Key period comments',
                  comments: widget.comments,
                  onAdd: widget.onAddComment,
                  onEdit: widget.onEditComment,
                  onDelete: widget.onDeleteComment,
                  enabled: widget.enabled,
                ),
            ],
          ],
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
