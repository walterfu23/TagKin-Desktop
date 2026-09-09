import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_name.dart';
import 'package:tagkin_desktop/persons/person_search.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';

/// Searchable picker of existing named people, or create a new name.
///
/// Returns [personId] when the user picks someone already in the account,
/// [name] to mint a new person from the typed text, or [createNew] when the
/// user chose **New person** without typing a name (the caller then prompts).
/// Cancel / skip returns null.
Future<({String? personId, String? name, bool createNew})?>
showPersonPickerDialog(
  BuildContext context, {
  required List<Person> persons,
  String title = 'Set name',
  Set<String> disabledPersonIds = const {},
  String disabledReason = 'already on this photo',
  List<String> inFolderPersonIds = const [],
  List<String> recentPersonIds = const [],
}) {
  return showDialog<({String? personId, String? name, bool createNew})>(
    context: context,
    builder: (ctx) => _PersonPickerDialog(
      persons: persons,
      title: title,
      disabledPersonIds: disabledPersonIds,
      disabledReason: disabledReason,
      inFolderPersonIds: inFolderPersonIds,
      recentPersonIds: recentPersonIds,
    ),
  );
}

class _PersonPickerDialog extends StatefulWidget {
  const _PersonPickerDialog({
    required this.persons,
    required this.title,
    required this.disabledPersonIds,
    required this.disabledReason,
    required this.inFolderPersonIds,
    required this.recentPersonIds,
  });

  final List<Person> persons;
  final String title;
  final Set<String> disabledPersonIds;
  final String disabledReason;
  final List<String> inFolderPersonIds;
  final List<String> recentPersonIds;

  @override
  State<_PersonPickerDialog> createState() => _PersonPickerDialogState();
}

class _PersonPickerDialogState extends State<_PersonPickerDialog> {
  late final TextEditingController _controller = TextEditingController();
  late final FocusNode _searchFocus = FocusNode(onKeyEvent: _onSearchKey);
  late final List<IndexedPerson> _indexed = indexPersons(widget.persons);
  String _query = '';
  int _highlight = -1;

  @override
  void dispose() {
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _moveHighlight(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _moveHighlight(-1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _highlight = -1;
    });
  }

  _PickerModel _model() {
    final typed = _controller.text.trim();
    final exact = findPersonByName(widget.persons, typed);
    // New person is always offered. A free typed name mints it directly; an
    // empty box (or a name already taken) defers naming to the caller.
    final createName = typed.isNotEmpty && exact == null ? typed : null;
    final q = personNameKey(_query);
    if (q.isEmpty) {
      final browse = browsePersons(
        indexed: _indexed,
        inFolderPersonIds: widget.inFolderPersonIds,
        recentPersonIds: widget.recentPersonIds,
      );
      return _PickerModel.fromBrowse(
        browse: browse,
        createName: createName,
        disabledPersonIds: widget.disabledPersonIds,
      );
    }
    final search = searchPersons(indexed: _indexed, query: _query);
    return _PickerModel.fromSearch(
      search: search,
      createName: createName,
      disabledPersonIds: widget.disabledPersonIds,
    );
  }

  List<int> _actionableIndices(_PickerModel model) {
    return [
      for (var i = 0; i < model.rows.length; i++)
        if (model.rows[i].isActionable) i,
    ];
  }

  int _clampedHighlight(_PickerModel model) {
    final rows = model.rows;
    if (rows.isEmpty) return 0;
    if (_highlight >= 0 &&
        _highlight < rows.length &&
        rows[_highlight].isActionable) {
      return _highlight;
    }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].kind == _RowKind.person && rows[i].isActionable) return i;
    }
    final actionable = _actionableIndices(model);
    return actionable.isEmpty ? 0 : actionable.first;
  }

  void _moveHighlight(int delta) {
    final model = _model();
    final actionable = _actionableIndices(model);
    if (actionable.isEmpty) return;
    final current = _clampedHighlight(model);
    var pos = 0;
    for (var i = 0; i < actionable.length; i++) {
      if (actionable[i] == current) {
        pos = i;
        break;
      }
    }
    var next = (pos + delta) % actionable.length;
    if (next < 0) next += actionable.length;
    setState(() => _highlight = actionable[next]);
  }

  void _commitHighlight() {
    final model = _model();
    final index = _clampedHighlight(model);
    if (model.rows.isEmpty) return;
    _commitRow(model.rows[index]);
  }

  void _commitRow(_PickerRow row) {
    if (!row.isActionable) return;
    if (row.kind == _RowKind.create) {
      final name = row.createName?.trim() ?? '';
      Navigator.of(context).pop(
        name.isEmpty
            ? (personId: null, name: null, createNew: true)
            : (personId: null, name: name, createNew: false),
      );
      return;
    }
    final person = row.person;
    if (person == null) return;
    Navigator.of(
      context,
    ).pop((personId: person.id, name: null, createNew: false));
  }

  @override
  Widget build(BuildContext context) {
    final model = _model();
    final rows = model.rows;
    final highlight = _clampedHighlight(model);

    return AlertDialog(
      key: const Key('person-picker-dialog'),
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('person-picker-search'),
              controller: _controller,
              focusNode: _searchFocus,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Person name',
                hintText: 'Search people, or type a new name',
                border: OutlineInputBorder(),
              ),
              onChanged: _onQueryChanged,
              onSubmitted: (_) => _commitHighlight(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ExcludeFocus(
                child: ListView.builder(
                  key: const Key('person-picker-list'),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    return _buildRow(
                      rows[index],
                      selected: index == highlight,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('person-picker-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _buildRow(_PickerRow row, {required bool selected}) {
    switch (row.kind) {
      case _RowKind.header:
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Text(
            row.title ?? '',
            key: Key('person-picker-section-${row.title}'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
        );
      case _RowKind.footer:
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: Text(
            'Showing ${row.shown} of ${row.total} — keep typing to narrow',
            key: const Key('person-picker-truncated'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      case _RowKind.emptyHint:
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
          child: Text(
            'No matching people — choose New person above.',
            key: const Key('person-picker-empty'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        );
      case _RowKind.create:
        final createName = row.createName;
        return ListTile(
          key: const Key('person-picker-create'),
          selected: selected,
          leading: const Icon(Icons.person_add_outlined),
          title: Text(
            createName == null
                ? 'New person'
                : 'Create new person "$createName"',
          ),
          onTap: () => _commitRow(row),
        );
      case _RowKind.person:
        final person = row.person!;
        final disabled = row.disabled;
        return ListTile(
          key: Key('person-picker-option-${person.id}'),
          selected: selected && !disabled,
          enabled: !disabled,
          leading: PersonListFaceThumb(personId: person.id, size: 36),
          title: Text(person.name),
          subtitle: disabled ? Text(widget.disabledReason) : null,
          onTap: disabled ? null : () => _commitRow(row),
        );
    }
  }
}

enum _RowKind { header, person, create, emptyHint, footer }

class _PickerRow {
  const _PickerRow.header(this.title)
      : kind = _RowKind.header,
        person = null,
        createName = null,
        shown = null,
        total = null,
        disabled = false;

  const _PickerRow.person(this.person, {required this.disabled})
      : kind = _RowKind.person,
        title = null,
        createName = null,
        shown = null,
        total = null;

  const _PickerRow.create(this.createName)
      : kind = _RowKind.create,
        person = null,
        title = null,
        shown = null,
        total = null,
        disabled = false;

  const _PickerRow.emptyHint()
      : kind = _RowKind.emptyHint,
        person = null,
        title = null,
        createName = null,
        shown = null,
        total = null,
        disabled = false;

  const _PickerRow.footer({required this.shown, required this.total})
      : kind = _RowKind.footer,
        person = null,
        title = null,
        createName = null,
        disabled = false;

  final _RowKind kind;
  final String? title;
  final Person? person;
  final String? createName;
  final int? shown;
  final int? total;
  final bool disabled;

  bool get isActionable =>
      (kind == _RowKind.person && !disabled) || kind == _RowKind.create;
}

class _PickerModel {
  const _PickerModel(this.rows);

  factory _PickerModel.fromSearch({
    required PersonSearchResult search,
    required String? createName,
    required Set<String> disabledPersonIds,
  }) {
    return _PickerModel([
      _PickerRow.create(createName),
      for (final hit in search.hits)
        _PickerRow.person(
          hit.person,
          disabled: disabledPersonIds.contains(hit.person.id),
        ),
      if (search.hits.isEmpty) const _PickerRow.emptyHint(),
      if (search.truncated)
        _PickerRow.footer(shown: search.hits.length, total: search.total),
    ]);
  }

  factory _PickerModel.fromBrowse({
    required PersonBrowseResult browse,
    required String? createName,
    required Set<String> disabledPersonIds,
  }) {
    return _PickerModel([
      _PickerRow.create(createName),
      for (final section in browse.sections) ...[
        _PickerRow.header(section.title),
        for (final person in section.persons)
          _PickerRow.person(
            person,
            disabled: disabledPersonIds.contains(person.id),
          ),
      ],
      if (browse.sections.isEmpty) const _PickerRow.emptyHint(),
      if (browse.truncated)
        _PickerRow.footer(shown: browse.shown, total: browse.total),
    ]);
  }

  final List<_PickerRow> rows;
}
