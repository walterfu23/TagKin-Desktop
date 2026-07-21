import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart' show itemsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/knowledge/comments_view.dart';
import 'package:tagkin_desktop/knowledge/corrections_history_view.dart';
import 'package:tagkin_desktop/knowledge/tag_edit_dialog.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';
import 'package:tagkin_desktop/review/key_period_scrubber.dart';
import 'package:tagkin_desktop/review/knowledge_view.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/review/media_viewer.dart';
import 'package:tagkin_desktop/review/review_controller.dart';

/// Review surface: local media + approved knowledge + corrections/comments.
///
/// Embedded below D2/D7 metadata on the item detail screen. D9 adds
/// Find person matches + appearance → person navigation. D10 owns tag /
/// captured-at / key-period corrections, undo, and comments.
class ItemReviewSection extends ConsumerStatefulWidget {
  const ItemReviewSection({
    super.key,
    required this.itemId,
    this.openVideo = true,
  });

  final String itemId;

  /// When false, skips native media_kit open (widget tests).
  final bool openVideo;

  @override
  ConsumerState<ItemReviewSection> createState() => _ItemReviewSectionState();
}

class _ItemReviewSectionState extends ConsumerState<ItemReviewSection> {
  Player? _player;
  VideoController? _videoController;
  String? _openedPath;
  bool _linking = false;
  String? _linkStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(reviewControllerProvider(widget.itemId)).load();
    });
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  void _disposePlayer() {
    _player?.dispose();
    _player = null;
    _videoController = null;
    _openedPath = null;
  }

  Future<void> _ensureVideoOpen(LocalMediaResolution media) async {
    if (!widget.openVideo) return;
    if (!media.isAvailable) return;
    final path = media.path;
    if (path == null || path == _openedPath) return;

    _disposePlayer();
    try {
      final opened = await openLocalVideo(media.file!);
      if (!mounted) {
        await opened.player.dispose();
        return;
      }
      setState(() {
        _player = opened.player;
        _videoController = opened.controller;
        _openedPath = path;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _player = null;
        _videoController = null;
        _openedPath = null;
      });
    }
  }

  Future<void> _linkPeople() async {
    if (_linking) return;
    setState(() {
      _linking = true;
      _linkStatus = null;
    });
    try {
      final result = await ref
          .read(itemsRepositoryProvider)
          .linkPeopleForItem(widget.itemId);
      if (!mounted) return;
      setState(() {
        _linkStatus =
            'Found ${result.appearances.length} appearance link(s)';
      });
      await ref.read(reviewControllerProvider(widget.itemId)).load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _linkStatus = 'Find person matches failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _linking = false);
      }
    }
  }

  Future<void> _openPerson(String personId) async {
    final container = ProviderScope.containerOf(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: PersonDetailPage(personId: personId),
        ),
      ),
    );
    if (mounted) {
      await ref.read(reviewControllerProvider(widget.itemId)).load();
    }
  }

  Future<void> _addTag(ReviewController review, String dimension) async {
    final result = await showTagEditDialog(
      context,
      initialDimension: dimension,
      lockDimension: true,
    );
    if (result == null) return;
    await review.addTag(dimension: result.dimension, value: result.value);
  }

  Future<void> _editTag(ReviewController review, Tag tag) async {
    final result = await showTagEditDialog(
      context,
      initialDimension: tag.dimension,
      initialValue: tag.value,
      lockDimension: true,
    );
    if (result == null) return;
    await review.editTag(tag.id, result.value);
  }

  Future<void> _editBounds(
    ReviewController review,
    KeyPeriodKnowledge period,
  ) async {
    final result = await showKeyPeriodBoundsDialog(
      context,
      startMs: period.startMs,
      endMs: period.endMs,
    );
    if (result == null) return;
    await review.correctKeyPeriodBounds(
      keyPeriodId: period.id,
      startMs: result.startMs,
      endMs: result.endMs,
    );
  }

  Future<void> _editCapturedAt(ReviewController review) async {
    final current = review.knowledge?.item.capturedAt;
    DateTime initial = DateTime.now();
    if (current != null) {
      initial = DateTime.tryParse(current) ?? initial;
    }
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final combined = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).toUtc();
    await review.correctCapturedAt(combined.toIso8601String());
  }

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(reviewControllerProvider(widget.itemId));

    return ListenableBuilder(
      listenable: review,
      builder: (context, _) {
        final knowledge = review.knowledge;
        final media = review.media;
        if (knowledge != null &&
            media != null &&
            knowledge.item.type == ItemType.video &&
            media.isAvailable) {
          // Schedule open after this frame (avoid setState during build).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureVideoOpen(media);
          });
        }

        return Column(
          key: const Key('item-review'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Review',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (review.phase == ReviewPhase.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: CircularProgressIndicator(
                    key: Key('review-loading'),
                  ),
                ),
              )
            else if (review.phase == ReviewPhase.error)
              _ReviewError(
                error: review.error!,
                onRetry: () => review.load(),
              )
            else if (knowledge != null && media != null) ...[
              _MediaStatusBanner(resolution: media),
              const SizedBox(height: 12),
              MediaViewer(
                itemType: knowledge.item.type,
                resolution: media,
                player: _player,
                videoController: _videoController,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'capturedAt: ${knowledge.item.capturedAt ?? '—'}',
                      key: const Key('review-captured-at'),
                    ),
                  ),
                  TextButton(
                    key: const Key('captured-at-edit'),
                    onPressed: review.isBusy
                        ? null
                        : () => _editCapturedAt(review),
                    child: const Text('Edit'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              KnowledgeView(
                knowledge: knowledge,
                onPersonTap: _openPerson,
                onAddTag: (d) => _addTag(review, d),
                onEditTag: (t) => _editTag(review, t),
                onRemoveTag: (t) => review.removeTag(t.id),
                correctionsEnabled: !review.isBusy,
              ),
              if (review.mutationError != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${review.mutationError}',
                  key: const Key('correction-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 16),
              CorrectionsHistoryView(
                corrections: knowledge.corrections,
                onUndo: review.undoCorrection,
                enabled: !review.isBusy,
              ),
              const SizedBox(height: 16),
              CommentsView(
                comments: review.itemComments,
                onAdd: review.addItemComment,
                onEdit: review.editComment,
                onDelete: review.deleteComment,
                enabled: !review.isBusy,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const Key('item-link-people'),
                onPressed: _linking ? null : _linkPeople,
                child: Text(
                  _linking ? 'Finding matches…' : 'Find person matches',
                ),
              ),
              if (_linkStatus != null) ...[
                const SizedBox(height: 8),
                Text(
                  _linkStatus!,
                  key: const Key('link-people-status'),
                ),
              ],
              if (knowledge.item.type == ItemType.video) ...[
                const SizedBox(height: 16),
                KeyPeriodScrubber(
                  keyPeriods: knowledge.keyPeriods,
                  player: _player,
                  onEditBounds: (p) => _editBounds(review, p),
                  commentsFor: review.commentsForKeyPeriod,
                  onAddComment: review.addKeyPeriodComment,
                  onEditComment: review.editComment,
                  onDeleteComment: review.deleteComment,
                  correctionsEnabled: !review.isBusy,
                ),
              ],
            ],
          ],
        );
      },
    );
  }
}

class _ReviewError extends StatelessWidget {
  const _ReviewError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isNotFound =
        error is ApiException && (error as ApiException).statusCode == 404;
    return Column(
      children: [
        Text(
          isNotFound
              ? 'Knowledge not found'
              : 'Could not load knowledge: $error',
          key: isNotFound
              ? const Key('review-not-found')
              : const Key('review-error'),
          textAlign: TextAlign.center,
        ),
        if (!isNotFound) ...[
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('review-retry'),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ],
    );
  }
}

class _MediaStatusBanner extends StatelessWidget {
  const _MediaStatusBanner({required this.resolution});

  final LocalMediaResolution resolution;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Key key;
    switch (resolution.status) {
      case LocalMediaStatus.available:
        label = 'Local media verified (contentHash match).';
        key = const Key('media-status-available');
      case LocalMediaStatus.missing:
        label = 'Local media missing.';
        key = const Key('media-status-missing');
      case LocalMediaStatus.hashMismatch:
        label = 'Local media contentHash mismatch.';
        key = const Key('media-status-hash-mismatch');
      case LocalMediaStatus.unsupported:
        label = 'Local media not supported for this source.';
        key = const Key('media-status-unsupported');
    }
    return Text(label, key: key);
  }
}
