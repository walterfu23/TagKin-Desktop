import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/range_slider_control.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Desktop preferences (Where, Library, Ingest, Video, Faces, Jobs).
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
  late int _jobsPollIntervalSeconds;

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
    _jobsPollIntervalSeconds = prefs.jobsPollIntervalSeconds;
  }

  void _disposeDraftControllers() {
    _familiarRegions.dispose();
  }

  @override
  void dispose() {
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
      'jobs.pollIntervalSeconds': _jobsPollIntervalSeconds,
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
        Navigator.of(context).pop();
      case _SettingsLeaveChoice.save:
        await _save();
      case _SettingsLeaveChoice.cancel:
      case null:
        break;
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
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
            onChanged: (v) => setState(() => onChanged(v)),
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
            onChanged: (v) => setState(() => onChanged(v)),
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
      child: SelectableScope(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Settings'),
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
              _sectionTitle('Where labels'),
              SwitchListTile(
                key: const Key('pref-show-country-same'),
                title: const Text('Show country when in the same country'),
                subtitle: const Text(
                  'Off (default): omit country when the photo matches '
                  'this computer’s country.',
                ),
                value: _showCountryWhenSameCountry,
                onChanged: (v) =>
                    setState(() => _showCountryWhenSameCountry = v),
              ),
              SwitchListTile(
                key: const Key('pref-show-state-same'),
                title: const Text('Show state/province when familiar'),
                subtitle: const Text(
                  'Off (default): omit state/province when it matches a '
                  'Familiar state/province below.',
                ),
                value: _showStateWhenSameState,
                onChanged: (v) => setState(() => _showStateWhenSameState = v),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  key: const Key('pref-familiar-regions'),
                  controller: _familiarRegions,
                  decoration: const InputDecoration(
                    labelText: 'Familiar state/province',
                    hintText: 'e.g. California, Nevada, BC',
                    helperText:
                        'Comma-separated. Leave blank to always show state/province. '
                        'You can also add from the Where column on Folders.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              _sectionTitle('Library'),
              SwitchListTile(
                key: const Key('pref-multi-column-sort'),
                title: const Text('Multi-column sort'),
                subtitle: const Text(
                  'Off (default): one sort column. On: click columns to build '
                  'a priority stack (1, 2, …).',
                ),
                value: _multiColumnSort,
                onChanged: (v) => setState(() => _multiColumnSort = v),
              ),
              _intSlider(
                key: const Key('pref-library-page-size'),
                label: 'Rows per page',
                helper: 'Default 50 (2–200).',
                value: _libraryPageSize,
                min: DesktopPrefs.libraryPageSizeMin,
                max: DesktopPrefs.libraryPageSizeMax,
                step: DesktopPrefs.libraryPageSizeStep,
                onChanged: (v) => _libraryPageSize = v,
              ),
              _intSlider(
                key: const Key('pref-recent-collections-limit'),
                label: 'Recent collections limit',
                helper: 'Default 20 (1–100). Open Recent / start gate.',
                value: _recentCollectionsLimit,
                min: DesktopPrefs.recentCollectionsLimitMin,
                max: DesktopPrefs.recentCollectionsLimitMax,
                step: DesktopPrefs.recentCollectionsLimitStep,
                onChanged: (v) => _recentCollectionsLimit = v,
              ),
              _sectionTitle('Review'),
              SwitchListTile(
                key: const Key('pref-show-face-overlays'),
                title: const Text('Show face boxes on photos'),
                subtitle: const Text(
                  'On (default): draw a labeled square for each who tag '
                  'that has a face region from analysis.',
                ),
                value: _showFaceOverlays,
                onChanged: (v) => setState(() => _showFaceOverlays = v),
              ),
              _sectionTitle('Ingest'),
              _intSlider(
                key: const Key('pref-near-duplicate-threshold'),
                label: 'Near-duplicate Hamming threshold',
                helper: 'Default 4. Lower = stricter matching.',
                value: _nearDuplicateThreshold,
                min: DesktopPrefs.nearDuplicateThresholdMin,
                max: DesktopPrefs.nearDuplicateThresholdMax,
                step: DesktopPrefs.nearDuplicateThresholdStep,
                onChanged: (v) => _nearDuplicateThreshold = v,
              ),
              _sectionTitle('Video / pre-pass'),
              _intSlider(
                key: const Key('pref-sample-min-interval'),
                label: 'Min sample interval (ms)',
                helper: 'Default 1000. Spacing in short key periods.',
                value: _sampleMinIntervalMs,
                min: DesktopPrefs.sampleMinIntervalMsMin,
                max: DesktopPrefs.sampleMinIntervalMsMax,
                step: DesktopPrefs.sampleMinIntervalMsStep,
                onChanged: (v) => _sampleMinIntervalMs = v,
              ),
              _intSlider(
                key: const Key('pref-sample-max-interval'),
                label: 'Max sample interval (ms)',
                helper: 'Default 15000. Spacing in long key periods.',
                value: _sampleMaxIntervalMs,
                min: DesktopPrefs.sampleMaxIntervalMsMin,
                max: DesktopPrefs.sampleMaxIntervalMsMax,
                step: DesktopPrefs.sampleMaxIntervalMsStep,
                onChanged: (v) => _sampleMaxIntervalMs = v,
              ),
              _intSlider(
                key: const Key('pref-soft-max-frames'),
                label: 'Soft max frames per video',
                helper: 'Default 500.',
                value: _softMaxFramesPerItem,
                min: DesktopPrefs.softMaxFramesPerItemMin,
                max: DesktopPrefs.softMaxFramesPerItemMax,
                step: DesktopPrefs.softMaxFramesPerItemStep,
                onChanged: (v) => _softMaxFramesPerItem = v,
              ),
              _doubleSlider(
                key: const Key('pref-scene-cut-threshold'),
                label: 'Scene-cut threshold',
                helper: 'Default 0.3. Lower detects more cuts.',
                value: _sceneCutThreshold,
                min: DesktopPrefs.sceneCutThresholdMin,
                max: DesktopPrefs.sceneCutThresholdMax,
                step: DesktopPrefs.sceneCutThresholdStep,
                onChanged: (v) => _sceneCutThreshold = v,
              ),
              _sectionTitle('Faces'),
              _doubleSlider(
                key: const Key('pref-faces-detect-score'),
                label: 'Face detect score threshold',
                helper: 'Default 0.2. Local SCRFD score floor.',
                value: _facesDetectScoreThreshold,
                min: DesktopPrefs.facesDetectScoreThresholdMin,
                max: DesktopPrefs.facesDetectScoreThresholdMax,
                step: DesktopPrefs.facesDetectScoreThresholdStep,
                onChanged: (v) => _facesDetectScoreThreshold = v,
              ),
              _intSlider(
                key: const Key('pref-faces-tray-page-limit'),
                label: 'Faces tray fetch limit',
                helper: 'Default 500 (50–500). API appearances page size.',
                value: _facesTrayPageLimit,
                min: DesktopPrefs.facesTrayPageLimitMin,
                max: DesktopPrefs.facesTrayPageLimitMax,
                step: DesktopPrefs.facesTrayPageLimitStep,
                onChanged: (v) => _facesTrayPageLimit = v,
              ),
              _sectionTitle('Jobs'),
              _intSlider(
                key: const Key('pref-jobs-poll-interval'),
                label: 'Job poll interval (seconds)',
                helper: 'Default 2 (1–30).',
                value: _jobsPollIntervalSeconds,
                min: DesktopPrefs.jobsPollIntervalSecondsMin,
                max: DesktopPrefs.jobsPollIntervalSecondsMax,
                step: DesktopPrefs.jobsPollIntervalSecondsStep,
                onChanged: (v) => _jobsPollIntervalSeconds = v,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SettingsLeaveChoice { discard, cancel, save }
