import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/folder_row_editor.dart';
import 'package:tagkin_desktop/library/folder_who_editor.dart';
import 'package:tagkin_desktop/library/item_hover_preview.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/person_assign_control.dart'
    show promptAssignPerson;
import 'package:tagkin_desktop/review/face_name_conflict_dialog.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';

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
    final personId = appearance?.personId;
    final assigned = personId != null && personId.isNotEmpty;
    faces.add(
      HoverPreviewFace(
        number: number,
        region: region,
        tagId: tag.id,
        assigned: assigned,
        personName: personName(personId),
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
      if (seen.add(
        dimension == 'what'
            ? '${tag.personId ?? ''}|${tag.value.toLowerCase()}'
            : tag.value.toLowerCase(),
      ))
        tag,
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
    final currentPeriod = period;
    final periodTags = currentPeriod == null
        ? const <Tag>[]
        : groupPeriodTagsByDimension(currentPeriod)[dimension] ?? const <Tag>[];
    final inherited = currentPeriod != null && periodTags.isEmpty;
    final cityScope = dimension != 'where'
        ? const <Tag>[]
        : inherited
        ? groupItemLevelTagsByDimension(knowledge.tags)['where'] ??
              const <Tag>[]
        : tags;
    final city = dimension == 'where' ? cityWhereTag(cityScope) : null;
    final scenes = dimension == 'where'
        ? [
            for (final tag in tags)
              if (!whereTagIsCity(tag)) tag,
          ]
        : tags;
    final suggestions = dimension == 'where'
        ? ref.read(libraryTableControllerProvider).cityNames()
        : const <String>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dimension == 'where')
          _ResolvedCityField(
            raw: city?.value ?? '',
            field: (display) => FolderCityField(
              key: Key('item-inline-where-city-$scopeId'),
              fieldKey: Key('item-inline-where-city-field-$scopeId'),
              optionKeyPrefix: 'item-inline-where-city-option-$scopeId',
              value: display,
              suggestions: suggestions,
              onCommit: (next) => _commitCity(
                ref,
                context,
                itemId: row.item.id,
                period: inherited ? null : period,
                city: city,
                next: next,
              ),
            ),
          ),
        for (final tag in scenes)
          if (dimension == 'what')
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WhatPersonMenu(
                  tag: tag,
                  namesById: ref
                      .watch(libraryTableControllerProvider)
                      .personNamesById,
                  onChanged: (personId) => _commitWhatPerson(
                    ref,
                    context,
                    itemId: row.item.id,
                    tag: tag,
                    personId: personId,
                  ),
                ),
                Expanded(
                  child: _CommitField(
                    key: Key('item-inline-$dimension-${tag.id}'),
                    fieldKey: Key('item-inline-$dimension-field-${tag.id}'),
                    value: tag.value,
                    hint: 'What',
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
                ),
              ],
            )
          else
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
            placeKind: dimension == 'where' ? PlaceKind.scene : null,
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
  PlaceKind? placeKind,
}) async {
  final trimmed = next.trim();
  if (tag == null && trimmed.isEmpty) return;
  if (tag != null && trimmed == tag.value) return;
  if (dimension == 'where') {
    ref.read(libraryTableControllerProvider).clearWhereLabelCache();
  }
  final review = await ref.read(folderRowEditorProvider).open(itemId);
  if (tag == null) {
    await review.addTag(
      dimension: dimension,
      value: trimmed,
      keyPeriodId: period?.id,
      placeKind: placeKind,
    );
  } else if (trimmed.isEmpty) {
    await review.removeTag(tag.id);
  } else {
    await review.editTag(tag.id, trimmed);
  }
  final error = review.mutationError;
  if (error != null) {
    if (context.mounted) _showSaveError(context);
    throw error;
  }
}

Future<void> _commitWhatPerson(
  WidgetRef ref,
  BuildContext context, {
  required String itemId,
  required Tag tag,
  required String? personId,
}) async {
  if (personId == tag.personId) return;
  final review = await ref.read(folderRowEditorProvider).open(itemId);
  await review.editTag(
    tag.id,
    tag.value,
    personId: personId,
    updatePerson: true,
  );
  final error = review.mutationError;
  if (error != null) {
    if (context.mounted) _showSaveError(context);
    throw error;
  }
}

/// Optional person for one What tag. Null clears the link.
class _WhatPersonMenu extends StatelessWidget {
  const _WhatPersonMenu({
    required this.tag,
    required this.namesById,
    required this.onChanged,
  });

  final Tag tag;
  final Map<String, String> namesById;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final names = namesById.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    final selected = tag.personId;
    final known = selected == null || namesById.containsKey(selected);
    return SizedBox(
      width: 112,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          key: Key('item-inline-what-person-${tag.id}'),
          isDense: true,
          isExpanded: true,
          value: selected,
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            if (!known)
              DropdownMenuItem<String?>(value: selected, child: Text(selected)),
            for (final person in names)
              DropdownMenuItem<String?>(
                value: person.key,
                child: Text(person.value),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _KeepExistingCity implements Exception {
  const _KeepExistingCity();
}

Future<void> _commitCity(
  WidgetRef ref,
  BuildContext context, {
  required String itemId,
  required KeyPeriodKnowledge? period,
  required Tag? city,
  required String next,
}) async {
  final trimmed = next.trim();
  if (city == null) {
    if (trimmed.isEmpty) return;
    await _commitTag(
      ref,
      context,
      itemId: itemId,
      dimension: 'where',
      period: period,
      tag: null,
      next: trimmed,
      placeKind: PlaceKind.city,
    );
    return;
  }
  if (trimmed == city.value.trim()) return;
  if (trimmed.isEmpty) {
    if (city.source == KnowledgeSource.metadata) {
      throw const _KeepExistingCity();
    }
    await _commitTag(
      ref,
      context,
      itemId: itemId,
      dimension: 'where',
      period: period,
      tag: city,
      next: '',
    );
    return;
  }
  await _commitTag(
    ref,
    context,
    itemId: itemId,
    dimension: 'where',
    period: period,
    tag: city,
    next: trimmed,
  );
}

/// Sets [name] on every item directly in [dir] that has no city yet.
Future<void> applyFolderCity(
  WidgetRef ref,
  BuildContext context, {
  required LibraryTableController controller,
  required String dir,
  required String name,
}) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return;
  final messenger = ScaffoldMessenger.of(context);
  final seen = <String>{};
  for (final row in controller.allRows) {
    if (row.sourceDir != dir) continue;
    if (!seen.add(row.item.id)) continue;
    final knowledge = row.knowledge;
    if (knowledge == null) continue;
    final existing = cityWhereTag(
      groupItemLevelTagsByDimension(knowledge.tags)['where'] ?? const <Tag>[],
    );
    if (existing != null) continue;
    final review = await ref.read(folderRowEditorProvider).open(row.item.id);
    await review.addTag(
      dimension: 'where',
      value: trimmed,
      placeKind: PlaceKind.city,
    );
    final error = review.mutationError;
    if (error != null) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not save')));
      throw error;
    }
  }
}

/// Shows a stored `lat,lng` city as its resolved label (`near <city>` or a name).
class _ResolvedCityField extends ConsumerStatefulWidget {
  const _ResolvedCityField({required this.raw, required this.field});

  final String raw;
  final Widget Function(String display) field;

  @override
  ConsumerState<_ResolvedCityField> createState() => _ResolvedCityFieldState();
}

class _ResolvedCityFieldState extends ConsumerState<_ResolvedCityField> {
  String? _resolved;

  @override
  void initState() {
    super.initState();
    _load(widget.raw);
  }

  @override
  void didUpdateWidget(_ResolvedCityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.raw != widget.raw) {
      _resolved = null;
      _load(widget.raw);
    }
  }

  void _load(String raw) {
    if (parseLatLngTag(raw) == null) return;
    ref.read(whereLabelResolverProvider).resolve(raw).then((label) {
      if (!mounted || widget.raw != raw) return;
      if (label.trim().isEmpty || label == raw) return;
      setState(() => _resolved = label);
    });
  }

  @override
  Widget build(BuildContext context) {
    final display = parseLatLngTag(widget.raw) == null
        ? widget.raw
        : (_resolved ?? widget.raw);
    return widget.field(display);
  }
}

/// City name field. Suggestions are city names already in the open library.
class FolderCityField extends StatefulWidget {
  const FolderCityField({
    super.key,
    required this.fieldKey,
    required this.optionKeyPrefix,
    required this.value,
    required this.suggestions,
    required this.onCommit,
    this.clearOnCommit = false,
  });

  final Key fieldKey;
  final String optionKeyPrefix;
  final String value;
  final List<String> suggestions;
  final Future<void> Function(String next) onCommit;
  final bool clearOnCommit;

  @override
  State<FolderCityField> createState() => _FolderCityFieldState();
}

class _FolderCityFieldState extends State<FolderCityField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  bool _committing = false;
  bool _picking = false;
  Future<void>? _pickInFlight;
  String? _committed;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focus = FocusNode()..addListener(_onFocus);
  }

  @override
  void didUpdateWidget(FolderCityField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == oldWidget.value) return;
    if (widget.value.trim() == _committed) _committed = null;
    if (!_focus.hasFocus) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _flushPending();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// A collapse unmounts the row while the field is still focused, which
  /// removes the focus listener before blur can save.
  void _flushPending() {
    if (_committing || _picking) return;
    final next = _controller.text.trim();
    if (next == widget.value.trim() || next == _committed) return;
    unawaited(widget.onCommit(_controller.text));
  }

  void _onFocus() {
    if (_focus.hasFocus || !_picking) setState(() {});
    if (!_focus.hasFocus && !_picking) unawaited(_commit());
  }

  List<String> get _matches {
    final query = _controller.text.trim().toLowerCase();
    final out = <String>[];
    for (final name in widget.suggestions) {
      if (query.isNotEmpty && !name.toLowerCase().contains(query)) continue;
      if (name.toLowerCase() == query) continue;
      out.add(name);
      if (out.length == 8) break;
    }
    return out;
  }

  Future<void> _commit() async {
    if (_committing) return;
    final next = _controller.text.trim();
    if (next == widget.value.trim() || next == _committed) return;
    _committing = true;
    _committed = next;
    try {
      await widget.onCommit(_controller.text);
      if (!mounted) return;
      if (widget.clearOnCommit) {
        _controller.text = '';
        _committed = null;
      }
    } on _KeepExistingCity {
      _committed = null;
      if (!mounted) return;
      _controller.text = widget.value;
    } catch (_) {
      _committed = null;
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

  void _beginPick(String name) {
    if (_pickInFlight != null) return;
    _picking = true;
    _controller.text = name;
    _pickInFlight = _finishPick();
  }

  Future<void> _finishPick() async {
    try {
      await _commit();
    } finally {
      _pickInFlight = null;
      if (mounted) _focus.unfocus();
      _picking = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final matches = _focus.hasFocus ? _matches : const <String>[];
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _revert},
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: widget.fieldKey,
              controller: _controller,
              focusNode: _focus,
              style: Theme.of(context).textTheme.bodySmall,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'City',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                unawaited(_commit());
                _focus.unfocus();
              },
            ),
            for (final name in matches)
              Align(
                alignment: Alignment.centerLeft,
                child: Listener(
                  onPointerDown: (_) => _beginPick(name),
                  child: TextButton(
                    key: Key('${widget.optionKeyPrefix}-$name'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => _beginPick(name),
                    child: Text(name),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

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
        onCommit: (next) =>
            _commitItemComment(ref, context, itemId: row.item.id, next: next),
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
  final review = await ref.read(folderRowEditorProvider).open(itemId);
  await review.saveItemComment(next);
  final error = review.mutationError;
  if (error != null) {
    if (context.mounted) _showSaveError(context);
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
    if (context.mounted) _showSaveError(context);
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
  @override
  Widget build(BuildContext context) {
    final persons = ref.watch(libraryTableControllerProvider).persons;
    final knowledge = widget.row.knowledge;
    if (knowledge == null) return const SizedBox.shrink();
    final period = widget.period;
    final crops = period == null
        ? whoFaceCropTags(knowledge)
        : whoFaceCropTagsForPeriod(knowledge, period.id);
    if (crops.isEmpty && period != null && itemHasWhoFaceCrops(knowledge)) {
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
    if (crops.isEmpty && knowledge.whoExclusions.isNotEmpty) {
      final assignments = period == null
          ? itemLevelPersonAssignments(knowledge)
          : const <PersonAppearance>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < assignments.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: _dropdownFor(
                persons: persons,
                key: Key('item-inline-who-item-${assignments[i].id}'),
                index: i,
                appearance: assignments[i],
                tagId: null,
              ),
            ),
          Text(
            'Excluded',
            key: Key('item-inline-who-excluded-${widget.scopeId}'),
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
                persons: persons,
                key: Key('item-inline-who-item-${assignments[i].id}'),
                index: i,
                appearance: assignments[i],
                tagId: null,
              ),
            ),
          _dropdownFor(
            persons: persons,
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
              persons: persons,
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
    required List<Person> persons,
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
      persons: persons,
      hint: hint,
      canExclude: tagId != null,
      onPick: (pick) => _commitPick(
        persons: persons,
        appearance: appearance,
        tagId: tagId,
        pick: pick,
      ),
    );
  }

  Future<void> _commitPick({
    required List<Person> persons,
    required PersonAppearance? appearance,
    required String? tagId,
    required _WhoPick pick,
  }) {
    final knowledge = widget.row.knowledge;
    final period = widget.period;
    return _commitFolderWhoPick(
      ref: ref,
      context: context,
      itemId: widget.row.item.id,
      appearance: appearance,
      tagId: tagId,
      persons: persons,
      pick: pick,
      knowledge: knowledge,
      crops: knowledge == null
          ? const []
          : period == null
          ? whoFaceCropTags(knowledge)
          : whoFaceCropTagsForPeriod(knowledge, period.id),
    );
  }
}

Future<void> _commitFolderWhoPick({
  required WidgetRef ref,
  required BuildContext context,
  required String itemId,
  required PersonAppearance? appearance,
  required String? tagId,
  required List<Person> persons,
  required _WhoPick pick,
  required ItemKnowledge? knowledge,
  required List<Tag> crops,
}) async {
  final who = ref.read(folderWhoEditorProvider);
  final WhoEditResult result;
  if (pick.exclude) {
    final id = tagId;
    if (id == null || id.isEmpty) return;
    result = await who.excludeFace(itemId: itemId, tagId: id);
  } else if (pick.unassign) {
    final id = appearance?.personId;
    if (appearance == null || id == null || id.isEmpty) return;
    result = await who.unassign(
      itemId: itemId,
      appearance: appearance,
      tagId: tagId,
      personName: _folderWhoName(ref, appearance),
    );
  } else {
    final personId = pick.personId;
    Person? match;
    if (personId != null) {
      for (final person in persons) {
        if (person.id == personId) match = person;
      }
    }
    PersonAppearance? takeFrom;
    if (tagId != null && knowledge != null) {
      final holderTag = whoCropHoldingPerson(
        knowledge: knowledge,
        tagId: tagId,
        personId: personId,
        name: pick.name,
        personNamesById: {for (final p in persons) p.id: p.name},
      );
      final holder = holderTag == null
          ? null
          : appearanceForWhoTag(knowledge, holderTag.id);
      if (holderTag != null &&
          holder != null &&
          holder.personId != null &&
          holder.personId!.isNotEmpty) {
        final takes = await showFaceNameConflictDialog(
          context,
          personName: _folderWhoName(ref, holder),
          target: ConflictFace(
            itemId: itemId,
            tagId: tagId,
            name: _folderWhoName(ref, appearance),
            number: _cropNumber(crops, tagId),
            knowledge: knowledge,
          ),
          holder: ConflictFace(
            itemId: itemId,
            tagId: holderTag.id,
            name: _folderWhoName(ref, holder),
            number: _cropNumber(crops, holderTag.id),
            knowledge: knowledge,
          ),
        );
        if (!takes || !context.mounted) return;
        takeFrom = holder;
      }
    }
    result = await who.assign(
      itemId: itemId,
      tagId: tagId,
      personId: takeFrom != null ? takeFrom.personId : personId,
      name: personId == null && takeFrom == null ? pick.name : null,
      existing: appearance,
      destName: takeFrom != null
          ? _folderWhoName(ref, takeFrom)
          : match?.name ?? pick.name ?? '',
      takeFrom: takeFrom,
    );
  }
  if (!context.mounted) return;
  final message = result.snackbar;
  if (message != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(key: const Key('folder-who-also-moved'), content: Text(message)),
    );
  }
}

int? _cropNumber(List<Tag> crops, String tagId) {
  final index = crops.indexWhere((tag) => tag.id == tagId);
  return index < 0 ? null : index + 1;
}

String _folderWhoName(WidgetRef ref, PersonAppearance? appearance) {
  final id = appearance?.personId;
  if (id == null || id.isEmpty) return '';
  return ref.read(libraryTableControllerProvider).personName(id) ?? '';
}

/// Who menu for one numbered face on the Folders Edit enlarged photo.
Future<void> pickFolderFaceWho({
  required WidgetRef ref,
  required BuildContext context,
  required LibraryTableRow row,
  required HoverPreviewFace face,
  required Rect box,
  KeyPeriodKnowledge? period,
}) async {
  final tagId = face.tagId;
  if (tagId == null || tagId.isEmpty) return;
  final knowledge = row.knowledge;
  if (knowledge == null) return;
  final appearance = appearanceForWhoTag(knowledge, tagId);
  final persons = ref.read(libraryTableControllerProvider).persons;
  final selected = await showMenu<String>(
    context: context,
    position: RelativeRect.fromRect(
      box,
      Offset.zero & MediaQuery.sizeOf(context),
    ),
    items: [
      PopupMenuItem(
        key: Key('hover-who-$tagId-new'),
        value: 'new',
        child: const Text('New person'),
      ),
      PopupMenuItem(
        key: Key('hover-who-$tagId-exclude'),
        value: 'exclude',
        child: const Text('Exclude'),
      ),
      if (face.assigned)
        PopupMenuItem(
          key: Key('hover-who-$tagId-unassigned'),
          value: 'unassign',
          child: const Text('Unassigned'),
        ),
      for (final person in persons)
        PopupMenuItem(
          key: Key('hover-who-$tagId-${person.id}'),
          value: person.id,
          child: Text(person.name, overflow: TextOverflow.ellipsis),
        ),
    ],
  );
  if (selected == null || !context.mounted) return;
  final _WhoPick pick;
  if (selected == 'new') {
    final resolved = await promptAssignPerson(context, persons: persons);
    if (resolved == null || !context.mounted) return;
    final id = resolved.personId;
    if (id != null && id == appearance?.personId) return;
    pick = id != null
        ? _WhoPick.person(id)
        : _WhoPick.newName(resolved.name ?? '');
  } else if (selected == 'exclude') {
    pick = const _WhoPick.exclude();
  } else if (selected == 'unassign') {
    pick = const _WhoPick.unassign();
  } else {
    pick = _WhoPick.person(selected);
  }
  try {
    await _commitFolderWhoPick(
      ref: ref,
      context: context,
      itemId: row.item.id,
      appearance: appearance,
      tagId: tagId,
      persons: persons,
      pick: pick,
      knowledge: knowledge,
      crops: period == null
          ? whoFaceCropTags(knowledge)
          : whoFaceCropTagsForPeriod(knowledge, period.id),
    );
  } catch (_) {
    if (context.mounted) _showSaveError(context);
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
      unassign = false,
      exclude = false;
  const _WhoPick.newName(this.name)
    : personId = null,
      unassign = false,
      exclude = false;
  const _WhoPick.unassign()
    : personId = null,
      name = null,
      unassign = true,
      exclude = false;
  const _WhoPick.exclude()
    : personId = null,
      name = null,
      unassign = false,
      exclude = true;

  final String? personId;
  final String? name;
  final bool unassign;
  final bool exclude;
}

/// One Who dropdown: New person, Exclude (face crops), Unassigned (when set),
/// then existing people. Saves as soon as an entry is picked.
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
    this.canExclude = false,
  });

  static const _newValue = '__new_person__';
  static const _excludeValue = '__exclude__';
  static const _unassignValue = '__unassign__';

  final Key fieldKey;
  final String optionKeyPrefix;
  final String? personId;
  final String? personName;
  final List<Person> persons;
  final Future<void> Function(_WhoPick pick) onPick;
  final String hint;
  final bool canExclude;

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
    } else if (value == _WhoDropdown._excludeValue) {
      pick = const _WhoPick.exclude();
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
      if (widget.canExclude)
        DropdownMenuItem(
          key: Key('${widget.optionKeyPrefix}-exclude'),
          value: _WhoDropdown._excludeValue,
          child: const Text('Exclude'),
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
  String? _submitted;

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
    if (!_committing) {
      final next = _controller.text.trim();
      if (next != widget.value.trim() && next != _submitted) {
        unawaited(widget.onCommit(_controller.text));
      }
    }
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
    if (next == widget.value.trim() || next == _submitted) return;
    _committing = true;
    _submitted = next;
    try {
      await widget.onCommit(_controller.text);
      if (!mounted) return;
      if (widget.clearOnCommit) _controller.text = '';
    } catch (_) {
      _submitted = null;
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
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _revert},
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
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Could not save')));
}
