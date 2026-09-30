import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart' show personsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/folder_row_editor.dart';
import 'package:tagkin_desktop/library/folder_who_editor.dart';
import 'package:tagkin_desktop/library/item_hover_preview.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/person_assign_control.dart'
    show promptAssignPerson;
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/ui/alpha_order.dart';

/// Face boxes for the enlarged thumb while Folders is in edit mode.
List<HoverPreviewFace> folderHoverFaces({
  required LibraryTableRow row,
  KeyPeriodKnowledge? period,
  required String? Function(String? personId) personName,
}) {
  final knowledge = row.knowledge;
  if (knowledge == null) return const [];
  final crops = period == null
      ? whoFaceCropTags(knowledge)
      : whoFaceCropTagsForPeriod(knowledge, period.id);
  final faces = <HoverPreviewFace>[];
  var number = 1;
  for (final tag in crops) {
    final region = tag.region;
    if (region == null) continue;
    final appearance = appearanceForWhoTag(knowledge, tag.id);
    faces.add(
      HoverPreviewFace(
        number: number,
        region: region,
        personName: personName(appearance?.personId),
      ),
    );
    number++;
  }
  return faces;
}

List<Tag> _dimensionTags({
  required ItemKnowledge knowledge,
  required String dimension,
  KeyPeriodKnowledge? period,
}) {
  final source = period == null
      ? groupDisplayTagsByDimension(knowledge)[dimension] ?? const <Tag>[]
      : groupPeriodTagsByDimension(period)[dimension] ?? const <Tag>[];
  final seen = <String>{};
  return [
    for (final tag in source)
      if (seen.add(tag.value.toLowerCase())) tag,
  ];
}

/// Inline What or Where fields for one Folders row.
class FolderInlineTags extends ConsumerWidget {
  const FolderInlineTags({
    super.key,
    required this.row,
    required this.scopeId,
    required this.dimension,
    this.period,
  });

  final LibraryTableRow row;
  final String scopeId;
  final String dimension;
  final KeyPeriodKnowledge? period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final knowledge = row.knowledge;
    if (knowledge == null) {
      return const SizedBox.shrink();
    }
    final tags = _dimensionTags(
      knowledge: knowledge,
      dimension: dimension,
      period: period,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final tag in tags)
          _CommitField(
            key: Key('item-inline-$dimension-${tag.id}'),
            fieldKey: Key('item-inline-$dimension-field-${tag.id}'),
            value: tag.value,
            hint: dimension == 'where' ? 'Where' : 'What',
            onCommit: (next) => _commitTag(
              ref,
              context,
              itemId: row.item.id,
              dimension: dimension,
              period: period,
              tag: tag,
              next: next,
            ),
          ),
        _CommitField(
          key: Key('item-inline-$dimension-add-$scopeId'),
          fieldKey: Key('item-inline-$dimension-add-field-$scopeId'),
          value: '',
          hint: 'Add',
          clearOnCommit: true,
          onCommit: (next) => _commitTag(
            ref,
            context,
            itemId: row.item.id,
            dimension: dimension,
            period: period,
            tag: null,
            next: next,
          ),
        ),
      ],
    );
  }
}

Future<void> _commitTag(
  WidgetRef ref,
  BuildContext context, {
  required String itemId,
  required String dimension,
  required KeyPeriodKnowledge? period,
  required Tag? tag,
  required String next,
}) async {
  final trimmed = next.trim();
  if (tag == null && trimmed.isEmpty) return;
  if (tag != null && trimmed == tag.value) return;
  final messenger = ScaffoldMessenger.of(context);
  if (dimension == 'where') {
    ref.read(libraryTableControllerProvider).clearWhereLabelCache();
  }
  final review = await ref.read(folderRowEditorProvider).open(itemId);
  if (tag == null) {
    await review.addTag(
      dimension: dimension,
      value: trimmed,
      keyPeriodId: period?.id,
    );
  } else if (trimmed.isEmpty) {
    await review.removeTag(tag.id);
  } else {
    await review.editTag(tag.id, trimmed);
  }
  final error = review.mutationError;
  if (error != null) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not save')));
    throw error;
  }
}

/// Inline Comment field(s) for one Folders row.
class FolderInlineComment extends ConsumerWidget {
  const FolderInlineComment({
    super.key,
    required this.row,
    required this.scopeId,
    this.period,
  });

  final LibraryTableRow row;
  final String scopeId;
  final KeyPeriodKnowledge? period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!row.commentsLoaded) return const SizedBox.shrink();
    final periodId = period?.id;
    final comments = [
      for (final comment in row.commentRecords)
        if (comment.deletedAt == null && comment.keyPeriodId == periodId)
          comment,
    ];
    if (periodId == null) {
      final existing = comments.isEmpty ? null : comments.first;
      return _CommitField(
        key: Key('item-inline-comment-$scopeId'),
        fieldKey: Key('item-inline-comment-field-$scopeId'),
        value: existing?.body ?? '',
        hint: 'Comment',
        maxLength: 128,
        onCommit: (next) => _commitItemComment(
          ref,
          context,
          itemId: row.item.id,
          next: next,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final comment in comments)
          _CommitField(
            key: Key('item-inline-comment-${comment.id}'),
            fieldKey: Key('item-inline-comment-field-${comment.id}'),
            value: comment.body,
            hint: 'Comment',
            maxLength: 128,
            onCommit: (next) => _commitPeriodComment(
              ref,
              context,
              itemId: row.item.id,
              periodId: periodId,
              comment: comment,
              next: next,
            ),
          ),
        _CommitField(
          key: Key('item-inline-comment-add-$scopeId'),
          fieldKey: Key('item-inline-comment-add-field-$scopeId'),
          value: '',
          hint: 'Add',
          maxLength: 128,
          clearOnCommit: true,
          onCommit: (next) => _commitPeriodComment(
            ref,
            context,
            itemId: row.item.id,
            periodId: periodId,
            comment: null,
            next: next,
          ),
        ),
      ],
    );
  }
}

Future<void> _commitItemComment(
  WidgetRef ref,
  BuildContext context, {
  required String itemId,
  required String next,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final review = await ref.read(folderRowEditorProvider).open(itemId);
  await review.saveItemComment(next);
  final error = review.mutationError;
  if (error != null) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not save')));
    throw error;
  }
}

Future<void> _commitPeriodComment(
  WidgetRef ref,
  BuildContext context, {
  required String itemId,
  required String periodId,
  required Comment? comment,
  required String next,
}) async {
  final trimmed = next.trim();
  if (comment == null && trimmed.isEmpty) return;
  if (trimmed.length > 128) return;
  final messenger = ScaffoldMessenger.of(context);
  final review = await ref.read(folderRowEditorProvider).open(itemId);
  if (comment == null) {
    await review.addKeyPeriodComment(periodId, trimmed);
  } else if (trimmed.isEmpty) {
    await review.deleteComment(comment.id);
  } else {
    await review.editComment(comment.id, trimmed);
  }
  final error = review.mutationError;
  if (error != null) {
    messenger.showSnackBar(const SnackBar(content: Text('Could not save')));
    throw error;
  }
}

/// Inline Who: one field per face, or one item-level field when there are
/// no face crops.
class FolderInlineWho extends ConsumerStatefulWidget {
  const FolderInlineWho({
    super.key,
    required this.row,
    required this.scopeId,
    this.period,
  });

  final LibraryTableRow row;
  final String scopeId;
  final KeyPeriodKnowledge? period;

  @override
  ConsumerState<FolderInlineWho> createState() => _FolderInlineWhoState();
}

class _FolderInlineWhoState extends ConsumerState<FolderInlineWho> {
  List<Person> _persons = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadPersons());
  }

  Future<void> _loadPersons() async {
    try {
      final people = await ref.read(personsRepositoryProvider).listPersons();
      if (!mounted) return;
      setState(() {
        _persons = sortedAlphaBy(people, (person) => person.name);
      });
    } catch (_) {
      // The field still accepts a typed name.
    }
  }

  @override
  Widget build(BuildContext context) {
    final knowledge = widget.row.knowledge;
    if (knowledge == null) return const SizedBox.shrink();
    final period = widget.period;
    final crops = period == null
        ? whoFaceCropTags(knowledge)
        : whoFaceCropTagsForPeriod(knowledge, period.id);
    if (crops.isEmpty &&
        period != null &&
        itemHasWhoFaceCrops(knowledge)) {
      final names = widget.row.summaryFor(period)?.who ?? widget.row.who;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(names.isEmpty ? '—' : names.join(', ')),
          Text(
            'Edit Who on the row that shows this face',
            key: Key('item-inline-who-readonly-${widget.scopeId}'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    if (crops.isEmpty) {
      final assignments = period == null
          ? itemLevelPersonAssignments(knowledge)
          : const <PersonAppearance>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < assignments.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _dropdownFor(
                key: Key('item-inline-who-item-${assignments[i].id}'),
                index: i,
                appearance: assignments[i],
                tagId: null,
              ),
            ),
          _dropdownFor(
            key: Key('item-inline-who-add-${widget.scopeId}'),
            fieldKey: Key('item-inline-who-add-field-${widget.scopeId}'),
            optionPrefix: 'item-inline-who-option-${widget.scopeId}-add',
            index: assignments.length,
            appearance: null,
            tagId: null,
            hint: 'Add person',
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < crops.length; i++)
          _FaceWhoRow(
            number: i + 1,
            scopeId: widget.scopeId,
            child: _dropdownFor(
              key: Key('item-inline-who-${crops[i].id}'),
              index: i,
              appearance: appearanceForWhoTag(knowledge, crops[i].id),
              tagId: crops[i].id,
            ),
          ),
      ],
    );
  }

  Widget _dropdownFor({
    required Key key,
    required int index,
    required PersonAppearance? appearance,
    required String? tagId,
    Key? fieldKey,
    String? optionPrefix,
    String hint = 'Who',
  }) {
    final rawId = appearance?.personId;
    final personId = rawId == null || rawId.isEmpty ? null : rawId;
    return _WhoDropdown(
      key: key,
      fieldKey:
          fieldKey ?? Key('item-inline-who-field-${widget.scopeId}-$index'),
      optionKeyPrefix:
          optionPrefix ?? 'item-inline-who-option-${widget.scopeId}-$index',
      personId: personId,
      personName: personId == null
          ? null
          : ref.read(libraryTableControllerProvider).personName(personId),
      persons: _persons,
      hint: hint,
      onPick: (pick) => _commitPick(
        appearance: appearance,
        tagId: tagId,
        pick: pick,
      ),
    );
  }

  String _nameOf(PersonAppearance? appearance) {
    final id = appearance?.personId;
    if (id == null || id.isEmpty) return '';
    return ref.read(libraryTableControllerProvider).personName(id) ?? '';
  }

  Future<void> _commitPick({
    required PersonAppearance? appearance,
    required String? tagId,
    required _WhoPick pick,
  }) async {
    final who = ref.read(folderWhoEditorProvider);
    final WhoEditResult result;
    if (pick.unassign) {
      final id = appearance?.personId;
      if (appearance == null || id == null || id.isEmpty) return;
      result = await who.unassign(
        itemId: widget.row.item.id,
        appearance: appearance,
        tagId: tagId,
        personName: _nameOf(appearance),
      );
    } else {
      final personId = pick.personId;
      Person? match;
      if (personId != null) {
        for (final person in _persons) {
          if (person.id == personId) match = person;
        }
      }
      result = await who.assign(
        itemId: widget.row.item.id,
        tagId: tagId,
        personId: personId,
        name: personId == null ? pick.name : null,
        existing: appearance,
        destName: match?.name ?? pick.name ?? '',
      );
      if (personId == null) unawaited(_loadPersons());
    }
    if (!mounted) return;
    final message = result.snackbar;
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const Key('folder-who-also-moved'),
          content: Text(message),
        ),
      );
    }
  }
}

class _FaceWhoRow extends StatelessWidget {
  const _FaceWhoRow({
    required this.number,
    required this.scopeId,
    required this.child,
  });

  final int number;
  final String scopeId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, right: 6),
            child: Text(
              '$number',
              key: Key('item-inline-who-badge-$scopeId-$number'),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _WhoPick {
  const _WhoPick.person(this.personId)
      : name = null,
        unassign = false;
  const _WhoPick.newName(this.name)
      : personId = null,
        unassign = false;
  const _WhoPick.unassign()
      : personId = null,
        name = null,
        unassign = true;

  final String? personId;
  final String? name;
  final bool unassign;
}

/// One Who dropdown: New person, Unassigned (when set), then existing people.
/// Saves as soon as an entry is picked.
class _WhoDropdown extends StatefulWidget {
  const _WhoDropdown({
    super.key,
    required this.fieldKey,
    required this.optionKeyPrefix,
    required this.personId,
    required this.personName,
    required this.persons,
    required this.onPick,
    this.hint = 'Who',
  });

  static const _newValue = '__new_person__';
  static const _unassignValue = '__unassign__';

  final Key fieldKey;
  final String optionKeyPrefix;
  final String? personId;
  final String? personName;
  final List<Person> persons;
  final Future<void> Function(_WhoPick pick) onPick;
  final String hint;

  @override
  State<_WhoDropdown> createState() => _WhoDropdownState();
}

class _WhoDropdownState extends State<_WhoDropdown> {
  bool _busy = false;

  Future<void> _onChanged(String? value) async {
    if (value == null || _busy) return;
    if (value == widget.personId) return;
    final _WhoPick pick;
    if (value == _WhoDropdown._newValue) {
      final resolved = await promptAssignPerson(
        context,
        persons: widget.persons,
      );
      if (resolved == null || !mounted) return;
      final id = resolved.personId;
      if (id != null && id == widget.personId) return;
      pick = id != null
          ? _WhoPick.person(id)
          : _WhoPick.newName(resolved.name ?? '');
    } else if (value == _WhoDropdown._unassignValue) {
      pick = const _WhoPick.unassign();
    } else {
      pick = _WhoPick.person(value);
    }
    setState(() => _busy = true);
    try {
      await widget.onPick(pick);
    } catch (_) {
      if (mounted) _showSaveError(context);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.personId;
    final known = current != null && widget.persons.any((p) => p.id == current);
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        key: Key('${widget.optionKeyPrefix}-new'),
        value: _WhoDropdown._newValue,
        child: const Text('New person'),
      ),
      if (current != null)
        DropdownMenuItem(
          key: Key('${widget.optionKeyPrefix}-unassigned'),
          value: _WhoDropdown._unassignValue,
          child: const Text('Unassigned'),
        ),
      if (current != null && !known)
        DropdownMenuItem(
          key: Key('${widget.optionKeyPrefix}-$current'),
          value: current,
          child: Text(widget.personName ?? '…'),
        ),
      for (final person in widget.persons)
        DropdownMenuItem(
          key: Key('${widget.optionKeyPrefix}-${person.id}'),
          value: person.id,
          child: Text(person.name, overflow: TextOverflow.ellipsis),
        ),
    ];
    return InputDecorator(
      decoration: const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: widget.fieldKey,
          isExpanded: true,
          isDense: true,
          value: current,
          hint: Text(widget.hint),
          items: items,
          onChanged: _busy ? null : _onChanged,
        ),
      ),
    );
  }
}

class _CommitField extends StatefulWidget {
  const _CommitField({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.onCommit,
    this.hint = '',
    this.maxLength,
    this.clearOnCommit = false,
  });

  final Key fieldKey;
  final String value;
  final Future<void> Function(String next) onCommit;
  final String hint;
  final int? maxLength;
  final bool clearOnCommit;

  @override
  State<_CommitField> createState() => _CommitFieldState();
}

class _CommitFieldState extends State<_CommitField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _committing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode()..addListener(_onFocus);
  }

  @override
  void didUpdateWidget(_CommitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && !_focus.hasFocus) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_focus.hasFocus) unawaited(_commit());
  }

  Future<void> _commit() async {
    if (_committing) return;
    final next = _controller.text.trim();
    if (next == widget.value.trim()) return;
    _committing = true;
    try {
      await widget.onCommit(_controller.text);
      if (!mounted) return;
      if (widget.clearOnCommit) _controller.text = '';
    } catch (_) {
      if (!mounted) return;
      _controller.text = widget.value;
    } finally {
      _committing = false;
    }
  }

  void _revert() {
    _controller.text = widget.value;
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _revert,
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: TextField(
          key: widget.fieldKey,
          controller: _controller,
          focusNode: _focus,
          style: Theme.of(context).textTheme.bodySmall,
          maxLength: widget.maxLength,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            isDense: true,
            hintText: widget.hint,
            counterText: '',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            unawaited(_commit());
            _focus.unfocus();
          },
        ),
      ),
    );
  }
}

void _showSaveError(BuildContext context) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Could not save')),
  );
}
