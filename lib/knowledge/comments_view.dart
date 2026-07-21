import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Item or key-period comment list with create / edit / delete (D10 / S9).
///
/// Author + timestamps come from the server; the client never fabricates
/// `authorUserId` (R10).
class CommentsView extends StatefulWidget {
  const CommentsView({
    super.key,
    required this.comments,
    this.title = 'Comments',
    this.onAdd,
    this.onEdit,
    this.onDelete,
    this.enabled = true,
    this.listKey,
  });

  final List<Comment> comments;
  final String title;
  final Future<void> Function(String body)? onAdd;
  final Future<void> Function(String commentId, String body)? onEdit;
  final Future<void> Function(String commentId)? onDelete;
  final bool enabled;

  /// Optional key for the list container (tests).
  final Key? listKey;

  @override
  State<CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<CommentsView> {
  final _body = TextEditingController();

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _body.text.trim();
    if (text.isEmpty || widget.onAdd == null || !widget.enabled) return;
    await widget.onAdd!(text);
    if (mounted) _body.clear();
  }

  Future<void> _edit(Comment comment) async {
    final controller = TextEditingController(text: comment.body);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('comment-edit-dialog'),
        title: const Text('Edit comment'),
        content: TextField(
          key: const Key('comment-edit-field'),
          controller: controller,
          autofocus: true,
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('comment-edit-save'),
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || widget.onEdit == null) return;
    await widget.onEdit!(comment.id, result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: widget.listKey ?? const Key('comments-view'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (widget.comments.isEmpty)
          const Text(
            'No comments yet.',
            key: Key('comments-empty'),
          )
        else
          for (final comment in widget.comments)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.body,
                    key: Key('comment-body-${comment.id}'),
                  ),
                  Text(
                    '${comment.authorUserId} · ${comment.createdAt}',
                    key: Key('comment-meta-${comment.id}'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  Row(
                    children: [
                      if (widget.onEdit != null)
                        TextButton(
                          key: Key('comment-edit-${comment.id}'),
                          onPressed: widget.enabled
                              ? () => _edit(comment)
                              : null,
                          child: const Text('Edit'),
                        ),
                      if (widget.onDelete != null)
                        TextButton(
                          key: Key('comment-delete-${comment.id}'),
                          onPressed: widget.enabled
                              ? () => widget.onDelete!(comment.id)
                              : null,
                          child: const Text('Delete'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        if (widget.onAdd != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('comment-body-field'),
                  controller: _body,
                  enabled: widget.enabled,
                  decoration: const InputDecoration(
                    labelText: 'Add a comment',
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('comment-add'),
                onPressed: widget.enabled ? _submit : null,
                child: const Text('Add'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
