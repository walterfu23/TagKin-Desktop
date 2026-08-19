import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/credits/credits_navigation.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/range_slider_control.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';
import 'package:tagkin_desktop/undo/undoable_action.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Desktop preferences (Where, Folders, Ingest, Video, Faces, Jobs).
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late DesktopPrefs _baseline;
  late bool _showCountryWhenSameCountry;
  late bool _showStateWhenSameState;
  late bool _multiColumnSort;
  late bool _showFaceOverlays;
  late TextEditingController _familiarRegions;
  late int _libraryPageSize;
  late int _recentCollectionsLimit;
  late int _nearDuplicateThreshold;
  late int _sampleMinIntervalMs;
  late int _sampleMaxIntervalMs;
  late int _softMaxFramesPerItem;
  late double _sceneCutThreshold;
  late double _facesDetectScoreThreshold;
  late int _facesTrayPageLimit;
  late int _personsListColumns;
  late bool _autoConfirmHighConfidencePersonMatches;
  late int _autoConfirmMinConfidencePercent;
  late int _jobsPollIntervalSeconds;
  late DateTimeDisplayFormat _dateTimeFormat;
  final UndoController _undoStack = UndoController();

  @override
  void initState() {
    super.initState();
    _baseline = ref.read(desktopPrefsProvider);
    _applyDraft(_baseline);
  }

  void _applyDraft(DesktopPrefs prefs) {
    _showCountryWhenSameCountry = prefs.showCountryWhenSameCountry;
    _showStateWhenSameState = prefs.showStateWhenSameState;
    _multiColumnSort = prefs.multiColumnSort;
    _showFaceOverlays = prefs.showFaceOverlays;
    _familiarRegions = TextEditingController(text: prefs.familiarRegions);
    _libraryPageSize = prefs.libraryPageSize;
    _recentCollectionsLimit = prefs.recentCollectionsLimit;
    _nearDuplicateThreshold = prefs.nearDuplicateThreshold;
    _sampleMinIntervalMs = prefs.sampleMinIntervalMs;
    _sampleMaxIntervalMs = prefs.sampleMaxIntervalMs;
    _softMaxFramesPerItem = prefs.softMaxFramesPerItem;
    _sceneCutThreshold = prefs.sceneCutThreshold;
    _facesDetectScoreThreshold = prefs.facesDetectScoreThreshold;
    _facesTrayPageLimit = prefs.facesTrayPageLimit;
    _personsListColumns = prefs.personsListColumns;
    _autoConfirmHighConfidencePersonMatches =
        prefs.autoConfirmHighConfidencePersonMatches;
    _autoConfirmMinConfidencePercent = prefs.autoConfirmMinConfidencePercent;
    _jobsPollIntervalSeconds = prefs.jobsPollIntervalSeconds;
    _dateTimeFormat = prefs.dateTimeFormatOrLocal;
  }

  /// Restore draft fields without recreating text controllers (undo/redo).
  void _restoreDraftSnapshot(DesktopPrefs prefs) {
    _showCountryWhenSameCountry = prefs.showCountryWhenSameCountry;
    _showStateWhenSameState = prefs.showStateWhenSameState;
    _multiColumnSort = prefs.multiColumnSort;
    _showFaceOverlays = prefs.showFaceOverlays;
    _familiarRegions.text = prefs.familiarRegions;
    _libraryPageSize = prefs.libraryPageSize;
    _recentCollectionsLimit = prefs.recentCollectionsLimit;
    _nearDuplicateThreshold = prefs.nearDuplicateThreshold;
    _sampleMinIntervalMs = prefs.sampleMinIntervalMs;
    _sampleMaxIntervalMs = prefs.sampleMaxIntervalMs;
    _softMaxFramesPerItem = prefs.softMaxFramesPerItem;
    _sceneCutThreshold = prefs.sceneCutThreshold;
    _facesDetectScoreThreshold = prefs.facesDetectScoreThreshold;
    _facesTrayPageLimit = prefs.facesTrayPageLimit;
    _personsListColumns = prefs.personsListColumns;
    _autoConfirmHighConfidencePersonMatches =
        prefs.autoConfirmHighConfidencePersonMatches;
    _autoConfirmMinConfidencePercent = prefs.autoConfirmMinConfidencePercent;
    _jobsPollIntervalSeconds = prefs.jobsPollIntervalSeconds;
    _dateTimeFormat = prefs.dateTimeFormatOrLocal;
  }

  void _mutateDraft(VoidCallback change, {String label = 'Edit setting'}) {
    final before = _draftPrefs();
    setState(change);
    final after = _draftPrefs();
    if (before == after) return;
    _undoStack.push(
      CallbackUndoableAction(
        label: label,
        onUndo: () async {
          setState(() => _restoreDraftSnapshot(before));
        },
        onRedo: () async {
          setState(() => _restoreDraftSnapshot(after));
        },
      ),
    );
  }

  void _disposeDraftControllers() {
    _familiarRegions.dispose();
  }

  @override
  void dispose() {
    _undoStack.dispose();
    _disposeDraftControllers();
    super.dispose();
  }

  DesktopPrefs _draftPrefs() {
    // Clamp via fromJson ranges; familiar CSV normalized on save path.
    return DesktopPrefs.fromJson({
      'where.showCountryWhenSameCountry': _showCountryWhenSameCountry,
      'where.showStateWhenSameState': _showStateWhenSameState,
      'ui.multiColumnSort': _multiColumnSort,
      'ui.showFaceOverlays': _showFaceOverlays,
      'where.familiarRegions':
          normalizeFamiliarRegionsCsv(_familiarRegions.text),
      'ui.libraryPageSize': _libraryPageSize,
      'ui.recentCollectionsLimit': _recentCollectionsLimit,
      'ingest.nearDuplicateThreshold': _nearDuplicateThreshold,
      'video.sampleMinIntervalMs': _sampleMinIntervalMs,
      'video.sampleMaxIntervalMs': _sampleMaxIntervalMs,
      'video.softMaxFramesPerItem': _softMaxFramesPerItem,
      'video.sceneCutThreshold': _sceneCutThreshold,
      'faces.detectScoreThreshold': _facesDetectScoreThreshold,
      'faces.trayPageLimit': _facesTrayPageLimit,
      'ui.personsListColumns': _personsListColumns,
      'faces.autoConfirmHighConfidencePersonMatches':
          _autoConfirmHighConfidencePersonMatches,
      'faces.autoConfirmMinConfidencePercent':
          _autoConfirmMinConfidencePercent,
      'jobs.pollIntervalSeconds': _jobsPollIntervalSeconds,
      'ui.dateTimeFormat': _dateTimeFormat.wire,
    });
  }

  bool get _isDirty => _draftPrefs() != _baseline;

  Future<void> _persist(DesktopPrefs next) async {
    final previous = ref.read(desktopPrefsProvider);
    await ref.read(desktopPrefsControllerProvider).update(next);

    try {
      ref.read(libraryTableControllerProvider).pageSize = next.libraryPageSize;
    } catch (_) {
      // Library not in tree (e.g. tests).
    }

    if (previous.multiColumnSort && !next.multiColumnSort) {
      try {
        ref.read(libraryTableControllerProvider).enforceSingleColumn();
      } catch (_) {}
    }

    final whereChanged =
        previous.showCountryWhenSameCountry !=
            next.showCountryWhenSameCountry ||
        previous.showStateWhenSameState != next.showStateWhenSameState ||
        previous.familiarRegions != next.familiarRegions;
    if (whereChanged) {
      try {
        ref.read(whereLabelResolverProvider).clearCache();
        await ref.read(libraryTableControllerProvider).refreshWhereLabels();
      } catch (_) {}
    }
  }

  Future<void> _save({bool pop = true}) async {
    final invalid = invalidFamiliarRegionTokens(_familiarRegions.text);
    if (invalid.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Invalid Familiar state/province: ${invalid.join(', ')}. '
            'Each entry needs at least one letter.',
          ),
        ),
      );
      return;
    }
    final next = _draftPrefs();
    await _persist(next);
    if (!mounted) return;
    _familiarRegions.text = next.familiarRegions;
    _baseline = next;
    _undoStack.clear();
    if (pop) Navigator.of(context).pop();
  }

  Future<void> _restoreDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore default settings?'),
        content: const Text(
          'All Settings values will be reset to their defaults. '
          'Collection page look is not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('settings-restore-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    await _persist(DesktopPrefs.defaults);
    _disposeDraftControllers();
    setState(() {
      _baseline = DesktopPrefs.defaults;
      _applyDraft(DesktopPrefs.defaults);
    });
    _undoStack.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings restored to defaults')),
    );
  }

  Future<void> _onPopAttempt() async {
    if (!_isDirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await showDialog<_SettingsLeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('settings-dirty-dialog'),
        title: const Text('Save settings?'),
        content: const Text(
          'You have unsaved changes. Save before leaving?',
        ),
        actions: [
          TextButton(
            key: const Key('settings-dirty-discard'),
            onPressed: () => Navigator.pop(ctx, _SettingsLeaveChoice.discard),
            child: const Text('Discard'),
          ),
          TextButton(
            key: const Key('settings-dirty-cancel'),
            onPressed: () => Navigator.pop(ctx, _SettingsLeaveChoice.cancel),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('settings-dirty-save'),
            onPressed: () => Navigator.pop(ctx, _SettingsLeaveChoice.save),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case _SettingsLeaveChoice.discard:
        _undoStack.clear();
        Navigator.of(context).pop();
      case _SettingsLeaveChoice.save:
        await _save();
      case _SettingsLeaveChoice.cancel:
      case null:
        break;
    }
  }

  Widget _settingsIntro() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Card(
      key: const Key('settings-intro'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'About these settings',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'These preferences apply across all collections. '
              'Defaults work for most people—change a section only when you '
              'need different behavior.',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
            const SizedBox(height: 6),
            Text(
              'Edits are not applied until you press Save. '
              'Restore defaults resets these Settings only '
              '(not each collection’s page look).',
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingsGroup({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _intSlider({
    required Key key,
    required String label,
    required String helper,
    required int value,
    required int min,
    required int max,
    required int step,
    required ValueChanged<int> onChanged,
    bool enabled = true,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            helper,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          RangeSliderControl(
            sliderKey: key,
            value: value,
            min: min,
            max: max,
            step: step,
            enabled: enabled,
            onChanged: (v) => _mutateDraft(() => onChanged(v)),
          ),
        ],
      ),
    );
  }

  Widget _doubleSlider({
    required Key key,
    required String label,
    required String helper,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 2),
          Text(
            helper,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          DoubleRangeSliderControl(
            sliderKey: key,
            value: value,
            min: min,
            max: max,
            step: step,
            onChanged: (v) => _mutateDraft(() => onChanged(v)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _onPopAttempt();
      },
      child: ActiveUndoHost(
        controller: _undoStack,
        child: UndoShortcuts(
        controller: _undoStack,
        child: SelectableScope(
        child: Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                const Text('Settings'),
                const SizedBox(width: 8),
                UndoDepthBadge(controller: _undoStack),
              ],
            ),
            actions: [
              TextButton(
                key: const Key('settings-restore'),
                onPressed: _restoreDefaults,
                child: const Text('Restore defaults'),
              ),
              TextButton(
                key: const Key('settings-save'),
                onPressed: () => _save(),
                child: const Text('Save'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _settingsIntro(),
              _settingsGroup(
                title: 'Display',
                subtitle:
                    'How dates and times appear. Values are still stored in UTC.',
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date and time format',
                        helperText:
                            'Default is this computer’s locale. Example: '
                            '${formatLocalDateTime(DateTime.now().toUtc().toIso8601String(), format: _dateTimeFormat)}',
                        border: const OutlineInputBorder(),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<DateTimeDisplayFormat>(
                          key: const Key('pref-date-time-format'),
                          value: _dateTimeFormat,
                          isExpanded: true,
                          items: [
                            for (final f in DateTimeDisplayFormat.values)
                              DropdownMenuItem(
                                value: f,
                                child: Text(f.settingsLabel),
                              ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            _mutateDraft(() => _dateTimeFormat = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              _settingsGroup(
                title: 'Where labels',
                subtitle:
                    'Shortens place text in the Folders “Where” column. '
                    'Leave defaults if you prefer full city / state / country.',
                children: [
                  SwitchListTile(
                    key: const Key('pref-show-country-same'),
                    title: const Text('Show country when in the same country'),
                    subtitle: const Text(
                      'Off (default): if a photo’s country matches this '
                      'computer’s country, hide the country name to keep '
                      'Where shorter. Turn on to always show country.',
                    ),
                    value: _showCountryWhenSameCountry,
                    onChanged: (v) =>
                        _mutateDraft(() => _showCountryWhenSameCountry = v),
                  ),
                  SwitchListTile(
                    key: const Key('pref-show-state-same'),
                    title: const Text('Show state/province when familiar'),
                    subtitle: const Text(
                      'Off (default): hide state/province when it matches an '
                      'entry in Familiar state/province below. Turn on to '
                      'always show state/province.',
                    ),
                    value: _showStateWhenSameState,
                    onChanged: (v) =>
                        _mutateDraft(() => _showStateWhenSameState = v),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: TextField(
                      key: const Key('pref-familiar-regions'),
                      controller: _familiarRegions,
                      decoration: const InputDecoration(
                        labelText: 'Familiar state/province',
                        hintText: 'e.g. California, Nevada, BC',
                        helperText:
                            'Places you already know—used to shorten Where when '
                            '“Show state/province when familiar” is off. '
                            'Comma-separated. Leave blank to always show '
                            'state/province. You can also add from the Where '
                            'column on Folders.',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              _settingsGroup(
                title: 'Folders',
                subtitle:
                    'How the Folders table sorts and pages, and how many '
                    'recent collections appear on Open Recent / the start gate.',
                children: [
                  SwitchListTile(
                    key: const Key('pref-multi-column-sort'),
                    title: const Text('Multi-column sort'),
                    subtitle: const Text(
                      'Off (default): clicking a column header sorts by that '
                      'column only. On: each click builds a priority stack '
                      '(1, 2, …) so you can sort by several columns at once.',
                    ),
                    value: _multiColumnSort,
                    onChanged: (v) => _mutateDraft(() => _multiColumnSort = v),
                  ),
                  _intSlider(
                    key: const Key('pref-library-page-size'),
                    label: 'Rows per page',
                    helper:
                        'How many items the Folders table shows before you '
                        'turn the page. Raise for fewer page flips; lower on '
                        'small screens. Default 50 (2–200).',
                    value: _libraryPageSize,
                    min: DesktopPrefs.libraryPageSizeMin,
                    max: DesktopPrefs.libraryPageSizeMax,
                    step: DesktopPrefs.libraryPageSizeStep,
                    onChanged: (v) => _libraryPageSize = v,
                  ),
                  _intSlider(
                    key: const Key('pref-recent-collections-limit'),
                    label: 'Recent collections limit',
                    helper:
                        'Max collections listed under Open Recent and on the '
                        'start gate. Raise if you juggle many collections. '
                        'Default 20 (1–100).',
                    value: _recentCollectionsLimit,
                    min: DesktopPrefs.recentCollectionsLimitMin,
                    max: DesktopPrefs.recentCollectionsLimitMax,
                    step: DesktopPrefs.recentCollectionsLimitStep,
                    onChanged: (v) => _recentCollectionsLimit = v,
                  ),
                ],
              ),
              _settingsGroup(
                title: 'Faces',
                subtitle:
                    'Boxes on the review photo plus how strict local face '
                    'finding is. Leave defaults unless faces are missed or '
                    'you see false detections.',
                children: [
                  SwitchListTile(
                    key: const Key('pref-show-face-overlays'),
                    title: const Text('Show face boxes on photos'),
                    subtitle: const Text(
                      'On (default): on the review photo, draw a labeled '
                      'square for each who-tag that has a face region from '
                      'analysis. Turn off for a cleaner photo view.',
                    ),
                    value: _showFaceOverlays,
                    onChanged: (v) => _mutateDraft(() => _showFaceOverlays = v),
                  ),
                  _doubleSlider(
                    key: const Key('pref-faces-detect-score'),
                    label: 'Face detect score threshold',
                    helper:
                        'Minimum confidence for the local face finder to keep '
                        'a detection. Raise if you see false boxes; lower if '
                        'real faces are missed. Default 0.2.',
                    value: _facesDetectScoreThreshold,
                    min: DesktopPrefs.facesDetectScoreThresholdMin,
                    max: DesktopPrefs.facesDetectScoreThresholdMax,
                    step: DesktopPrefs.facesDetectScoreThresholdStep,
                    onChanged: (v) => _facesDetectScoreThreshold = v,
                  ),
                  _intSlider(
                    key: const Key('pref-faces-tray-page-limit'),
                    label: 'Faces tray fetch limit',
                    helper:
                        'How many face appearances the Faces trays load per '
                        'request. Raise only if trays feel incomplete on huge '
                        'collections. Default 500 (50–500).',
                    value: _facesTrayPageLimit,
                    min: DesktopPrefs.facesTrayPageLimitMin,
                    max: DesktopPrefs.facesTrayPageLimitMax,
                    step: DesktopPrefs.facesTrayPageLimitStep,
                    onChanged: (v) => _facesTrayPageLimit = v,
                  ),
                  _intSlider(
                    key: const Key('pref-persons-list-columns'),
                    label: 'Persons list columns',
                    helper:
                        'How many person face crops sit in each row on the '
                        'Persons page. Default 5 (1–10).',
                    value: _personsListColumns,
                    min: DesktopPrefs.personsListColumnsMin,
                    max: DesktopPrefs.personsListColumnsMax,
                    step: DesktopPrefs.personsListColumnsStep,
                    onChanged: (v) => _personsListColumns = v,
                  ),
                  SwitchListTile(
                    key: const Key('pref-auto-confirm-high-confidence'),
                    title: const Text(
                      'Auto-confirm high-confidence person matches',
                    ),
                    subtitle: const Text(
                      'On (default): after analyze, lookalike faces that match '
                      'a named person are auto-confirmed when confidence is at '
                      'or above the percent below. Off: those matches stay '
                      'Unconfirmed until you Confirm or reject them.',
                    ),
                    value: _autoConfirmHighConfidencePersonMatches,
                    onChanged: (v) => _mutateDraft(
                      () => _autoConfirmHighConfidencePersonMatches = v,
                    ),
                  ),
                  _intSlider(
                    key: const Key('pref-auto-confirm-min-confidence'),
                    label: 'Auto-confirm minimum confidence (%)',
                    helper:
                        'Likeness confidence required to auto-confirm a named '
                        'person match. Lower auto-confirms more matches; raise '
                        'to review more Unconfirmed faces. Default 95 (0–100).',
                    value: _autoConfirmMinConfidencePercent,
                    min: DesktopPrefs.autoConfirmMinConfidencePercentMin,
                    max: DesktopPrefs.autoConfirmMinConfidencePercentMax,
                    step: DesktopPrefs.autoConfirmMinConfidencePercentStep,
                    enabled: _autoConfirmHighConfidencePersonMatches,
                    onChanged: (v) => _autoConfirmMinConfidencePercent = v,
                  ),
                ],
              ),
              _settingsGroup(
                title: 'Ingest & video',
                subtitle:
                    'How near-duplicates are detected when adding from a '
                    'folder, and how videos are sampled before analysis. '
                    'Leave defaults unless ingest is too slow or too aggressive.',
                children: [
                  _intSlider(
                    key: const Key('pref-near-duplicate-threshold'),
                    label: 'Near-duplicate Hamming threshold',
                    helper:
                        'How similar two photos must look (fingerprint '
                        'distance) to count as near-duplicates when adding '
                        'from a folder. Lower = stricter (fewer matches). '
                        'Default 4.',
                    value: _nearDuplicateThreshold,
                    min: DesktopPrefs.nearDuplicateThresholdMin,
                    max: DesktopPrefs.nearDuplicateThresholdMax,
                    step: DesktopPrefs.nearDuplicateThresholdStep,
                    onChanged: (v) => _nearDuplicateThreshold = v,
                  ),
                  _intSlider(
                    key: const Key('pref-sample-min-interval'),
                    label: 'Min sample interval (ms)',
                    helper:
                        'Closest spacing between video frames taken in short '
                        'stretches. Smaller = more frames (slower, more '
                        'thorough). Default 1000 ms.',
                    value: _sampleMinIntervalMs,
                    min: DesktopPrefs.sampleMinIntervalMsMin,
                    max: DesktopPrefs.sampleMinIntervalMsMax,
                    step: DesktopPrefs.sampleMinIntervalMsStep,
                    onChanged: (v) => _sampleMinIntervalMs = v,
                  ),
                  _intSlider(
                    key: const Key('pref-sample-max-interval'),
                    label: 'Max sample interval (ms)',
                    helper:
                        'Widest spacing between frames in long, uneventful '
                        'stretches. Smaller = denser sampling of long clips. '
                        'Default 15000 ms.',
                    value: _sampleMaxIntervalMs,
                    min: DesktopPrefs.sampleMaxIntervalMsMin,
                    max: DesktopPrefs.sampleMaxIntervalMsMax,
                    step: DesktopPrefs.sampleMaxIntervalMsStep,
                    onChanged: (v) => _sampleMaxIntervalMs = v,
                  ),
                  _intSlider(
                    key: const Key('pref-soft-max-frames'),
                    label: 'Soft max frames per video',
                    helper:
                        'Soft cap on sample frames taken from one video so '
                        'long clips stay manageable. Raise for longer '
                        'coverage; lower to speed up pre-pass. Default 500.',
                    value: _softMaxFramesPerItem,
                    min: DesktopPrefs.softMaxFramesPerItemMin,
                    max: DesktopPrefs.softMaxFramesPerItemMax,
                    step: DesktopPrefs.softMaxFramesPerItemStep,
                    onChanged: (v) => _softMaxFramesPerItem = v,
                  ),
                  _doubleSlider(
                    key: const Key('pref-scene-cut-threshold'),
                    label: 'Scene-cut threshold',
                    helper:
                        'Sensitivity for detecting cuts between scenes. '
                        'Lower finds more cuts (more samples around changes). '
                        'Default 0.3.',
                    value: _sceneCutThreshold,
                    min: DesktopPrefs.sceneCutThresholdMin,
                    max: DesktopPrefs.sceneCutThresholdMax,
                    step: DesktopPrefs.sceneCutThresholdStep,
                    onChanged: (v) => _sceneCutThreshold = v,
                  ),
                ],
              ),
              _settingsGroup(
                title: 'Jobs',
                subtitle:
                    'How often the app checks analyze / upload progress. '
                    'Leave the default unless the network is very slow.',
                children: [
                  _intSlider(
                    key: const Key('pref-jobs-poll-interval'),
                    label: 'Job poll interval (seconds)',
                    helper:
                        'Seconds between progress checks while analyze or '
                        'upload runs. Higher = less network chatter; lower = '
                        'snappier status. Default 2 (1–30).',
                    value: _jobsPollIntervalSeconds,
                    min: DesktopPrefs.jobsPollIntervalSecondsMin,
                    max: DesktopPrefs.jobsPollIntervalSecondsMax,
                    step: DesktopPrefs.jobsPollIntervalSecondsStep,
                    onChanged: (v) => _jobsPollIntervalSeconds = v,
                  ),
                ],
              ),
              _settingsGroup(
                title: 'Credits',
                subtitle:
                    'Buy a credit pack or add a card for the Trial pack. Credits do not expire.',
                children: [
                  ListTile(
                    key: const Key('settings-buy-credits'),
                    title: const Text('Buy credits'),
                    subtitle: const Text('Open Stripe Checkout in your browser'),
                    onTap: () => pushBuyCreditsPage(context),
                  ),
                  ListTile(
                    key: const Key('settings-trial-card'),
                    title: const Text('Card verification'),
                    subtitle: const Text(
                      'Required once before Trial credits become remaining credits',
                    ),
                    onTap: () => pushTrialCardPage(context),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}

enum _SettingsLeaveChoice { discard, cancel, save }
