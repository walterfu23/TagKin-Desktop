import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/processing_status_view.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';
import 'package:tagkin_desktop/where/where_value_text.dart';

/// Item-detail field group: two columns.
/// Left: Status, Type, Captured, Added, File.
/// Right: Who/What/When/Where, then Comment.
class ItemFieldsGroup extends ConsumerWidget {
  const ItemFieldsGroup({
    super.key,
    required this.item,
    this.knowledge,
    this.personNamesById = const {},
    this.whoPersonNames,
    this.omittedWhoTagIds = const {},
    this.commentText = '',
    this.commentEnabled = true,
    this.onCommentChanged,
  });

  final Item item;
  final ItemKnowledge? knowledge;
  final Map<String, String> personNamesById;

  /// When set, Who CSV uses these names instead of assigned appearances.
  final List<String>? whoPersonNames;

  /// Who-tag ids to omit from the Who CSV (draft exclude).
  final Set<String> omittedWhoTagIds;

  /// Draft item-level comment body (persisted only via page Save).
  final String commentText;
  final bool commentEnabled;
  final ValueChanged<String>? onCommentChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final format = ref.watch(desktopPrefsProvider).dateTimeFormatOrLocal;
    final grouped = knowledge == null
        ? null
        : groupItemLevelTagsByDimension(knowledge!.tags);
    final personNames = whoPersonNames ??
        (knowledge == null
            ? const <String>[]
            : assignedPersonNames(knowledge!, personNamesById));

    return Row(
      key: const Key('item-fields-group'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          key: const Key('item-fields-left'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FieldRow(
                label: 'Status',
                child: ProcessingStatusBadge(status: item.processingStatus),
              ),
              _FieldRow(
                label: 'Type',
                child: Text(
                  item.type == ItemType.video ? 'Video' : 'Photo',
                  key: const Key('item-type'),
                ),
              ),
              _FieldRow(
                label: 'Captured',
                child: Text(
                  formatLocalDateTime(item.capturedAt, format: format),
                  key: const Key('item-captured-at'),
                ),
              ),
              _FieldRow(
                label: 'Added',
                child: Text(
                  formatLocalDateTime(item.createdAt, format: format),
                  key: const Key('item-created-at'),
                ),
              ),
              if (localPathFromSourceRef(item.sourceRef) case final path?)
                _FieldRow(
                  label: 'File',
                  child: Text(
                    path,
                    key: const Key('item-file'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          key: const Key('item-fields-right'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                key: const Key('knowledge-view'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final dimension in kKnowledgeDimensions)
                    _KnowledgeField(
                      dimension: dimension,
                      values: grouped == null
                          ? const <String>[]
                          : knowledgeCsvValues(
                              dimension: dimension,
                              tags: grouped[dimension]!
                                  .where(
                                    (t) =>
                                        dimension != 'who' ||
                                        !omittedWhoTagIds.contains(t.id),
                                  )
                                  .toList(),
                              personNames:
                                  dimension == 'who' ? personNames : const [],
                            ),
                      tags: grouped?[dimension] ?? const [],
                      dateTimeFormat: format,
                    ),
                ],
              ),
              _FieldRow(
                label: 'Comment',
                labelKey: 'item-comment-label',
                child: _ItemCommentField(
                  text: commentText,
                  enabled: commentEnabled && onCommentChanged != null,
                  onChanged: onCommentChanged,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemCommentField extends StatefulWidget {
  const _ItemCommentField({
    required this.text,
    required this.enabled,
    this.onChanged,
  });

  final String text;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  State<_ItemCommentField> createState() => _ItemCommentFieldState();
}

class _ItemCommentFieldState extends State<_ItemCommentField> {
  static const _maxLen = 128;
  late final TextEditingController _body = TextEditingController(
    text: widget.text,
  );

  @override
  void didUpdateWidget(covariant _ItemCommentField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _body.text) {
      _body.value = TextEditingValue(
        text: widget.text,
        selection: TextSelection.collapsed(offset: widget.text.length),
      );
    }
  }

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onChanged == null) {
      final text = widget.text.trim();
      return Text(
        text.isEmpty ? '—' : text,
        key: const Key('item-comment-value'),
      );
    }
    return TextField(
      key: const Key('item-comment-field'),
      controller: _body,
      enabled: widget.enabled,
      maxLength: _maxLen,
      minLines: 1,
      maxLines: 4,
      decoration: const InputDecoration(
        hintText: '—',
        isDense: true,
        counterText: '',
      ),
      onChanged: widget.onChanged,
    );
  }
}

class _KnowledgeField extends StatelessWidget {
  const _KnowledgeField({
    required this.dimension,
    required this.values,
    required this.tags,
    required this.dateTimeFormat,
  });

  final String dimension;
  final List<String> values;
  final List<Tag> tags;
  final DateTimeDisplayFormat dateTimeFormat;

  String get _label =>
      '${dimension[0].toUpperCase()}${dimension.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final Widget value;
    if (values.isEmpty) {
      value = const Text('—');
    } else if (dimension == 'where') {
      value = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var i = 0; i < tags.length; i++) ...[
            if (i > 0) const Text(', '),
            WhereValueText(
              key: Key('tag-value-${tags[i].id}'),
              value: tags[i].value,
            ),
          ],
        ],
      );
    } else {
      final shown = dimension == 'when'
          ? [
              for (final v in values)
                formatLocalDateTime(v, format: dateTimeFormat),
            ]
          : values;
      value = Text(
        shown.join(', '),
        key: Key('knowledge-$dimension'),
      );
    }

    return _FieldRow(
      label: _label,
      labelKey: 'knowledge-dimension-$dimension',
      child: value,
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.label,
    required this.child,
    this.labelKey,
  });

  final String label;
  final Widget child;
  final String? labelKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              key: labelKey != null ? Key(labelKey!) : null,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
