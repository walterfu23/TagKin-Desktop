import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
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
  late TextEditingController _libraryPageSize;
  late TextEditingController _recentCollectionsLimit;
  late TextEditingController _nearDuplicateThreshold;
  late TextEditingController _sampleMinIntervalMs;
  late TextEditingController _sampleMaxIntervalMs;
  late TextEditingController _softMaxFramesPerItem;
  late TextEditingController _sceneCutThreshold;
  late TextEditingController _facesDetectScoreThreshold;
  late TextEditingController _facesTrayPageLimit;
  late TextEditingController _jobsPollIntervalSeconds;

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
    _libraryPageSize =
        TextEditingController(text: '${prefs.libraryPageSize}');
    _recentCollectionsLimit =
        TextEditingController(text: '${prefs.recentCollectionsLimit}');
    _nearDuplicateThreshold =
        TextEditingController(text: '${prefs.nearDuplicateThreshold}');
    _sampleMinIntervalMs =
        TextEditingController(text: '${prefs.sampleMinIntervalMs}');
    _sampleMaxIntervalMs =
        TextEditingController(text: '${prefs.sampleMaxIntervalMs}');
    _softMaxFramesPerItem =
        TextEditingController(text: '${prefs.softMaxFramesPerItem}');
    _sceneCutThreshold =
        TextEditingController(text: '${prefs.sceneCutThreshold}');
    _facesDetectScoreThreshold =
        TextEditingController(text: '${prefs.facesDetectScoreThreshold}');
    _facesTrayPageLimit =
        TextEditingController(text: '${prefs.facesTrayPageLimit}');
    _jobsPollIntervalSeconds =
        TextEditingController(text: '${prefs.jobsPollIntervalSeconds}');
  }

  void _disposeDraftControllers() {
    _familiarRegions.dispose();
    _libraryPageSize.dispose();
    _recentCollectionsLimit.dispose();
    _nearDuplicateThreshold.dispose();
    _sampleMinIntervalMs.dispose();
    _sampleMaxIntervalMs.dispose();
    _softMaxFramesPerItem.dispose();
    _sceneCutThreshold.dispose();
    _facesDetectScoreThreshold.dispose();
    _facesTrayPageLimit.dispose();
    _jobsPollIntervalSeconds.dispose();
  }

  @override
  void dispose() {
    _disposeDraftControllers();
    super.dispose();
  }

  DesktopPrefs _draftPrefs() {
    int parseInt(TextEditingController c, int fallback) =>
        int.tryParse(c.text.trim()) ?? fallback;
    double parseDouble(TextEditingController c, double fallback) =>
        double.tryParse(c.text.trim()) ?? fallback;

    // Clamp via fromJson ranges; familiar CSV normalized on save path.
    return DesktopPrefs.fromJson({
      'where.showCountryWhenSameCountry': _showCountryWhenSameCountry,
      'where.showStateWhenSameState': _showStateWhenSameState,
      'ui.multiColumnSort': _multiColumnSort,
      'ui.showFaceOverlays': _showFaceOverlays,
      'where.familiarRegions':
          normalizeFamiliarRegionsCsv(_familiarRegions.text),
      'ui.libraryPageSize':
          parseInt(_libraryPageSize, DesktopPrefs.defaults.libraryPageSize),
      'ui.recentCollectionsLimit': parseInt(
        _recentCollectionsLimit,
        DesktopPrefs.defaults.recentCollectionsLimit,
      ),
      'ingest.nearDuplicateThreshold': parseInt(
        _nearDuplicateThreshold,
        DesktopPrefs.defaults.nearDuplicateThreshold,
      ),
      'video.sampleMinIntervalMs': parseInt(
        _sampleMinIntervalMs,
        DesktopPrefs.defaults.sampleMinIntervalMs,
      ),
      'video.sampleMaxIntervalMs': parseInt(
        _sampleMaxIntervalMs,
        DesktopPrefs.defaults.sampleMaxIntervalMs,
      ),
      'video.softMaxFramesPerItem': parseInt(
        _softMaxFramesPerItem,
        DesktopPrefs.defaults.softMaxFramesPerItem,
      ),
      'video.sceneCutThreshold': parseDouble(
        _sceneCutThreshold,
        DesktopPrefs.defaults.sceneCutThreshold,
      ),
      'faces.detectScoreThreshold': parseDouble(
        _facesDetectScoreThreshold,
        DesktopPrefs.defaults.facesDetectScoreThreshold,
      ),
      'faces.trayPageLimit': parseInt(
        _facesTrayPageLimit,
        DesktopPrefs.defaults.facesTrayPageLimit,
      ),
      'jobs.pollIntervalSeconds': parseInt(
        _jobsPollIntervalSeconds,
        DesktopPrefs.defaults.jobsPollIntervalSeconds,
      ),
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

  Widget _intField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String helper,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        key: key,
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  Widget _doubleField({
    required Key key,
    required TextEditingController controller,
    required String label,
    required String helper,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        key: key,
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
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
              _intField(
                key: const Key('pref-library-page-size'),
                controller: _libraryPageSize,
                label: 'Rows per page',
                helper: 'Default 50 (2–200).',
              ),
              _intField(
                key: const Key('pref-recent-collections-limit'),
                controller: _recentCollectionsLimit,
                label: 'Recent collections limit',
                helper: 'Default 20 (1–100). Open Recent / start gate.',
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
              _intField(
                key: const Key('pref-near-duplicate-threshold'),
                controller: _nearDuplicateThreshold,
                label: 'Near-duplicate Hamming threshold',
                helper: 'Default 4. Lower = stricter matching.',
              ),
              _sectionTitle('Video / pre-pass'),
              _intField(
                key: const Key('pref-sample-min-interval'),
                controller: _sampleMinIntervalMs,
                label: 'Min sample interval (ms)',
                helper: 'Default 1000. Spacing in short key periods.',
              ),
              _intField(
                key: const Key('pref-sample-max-interval'),
                controller: _sampleMaxIntervalMs,
                label: 'Max sample interval (ms)',
                helper: 'Default 15000. Spacing in long key periods.',
              ),
              _intField(
                key: const Key('pref-soft-max-frames'),
                controller: _softMaxFramesPerItem,
                label: 'Soft max frames per video',
                helper: 'Default 500.',
              ),
              _doubleField(
                key: const Key('pref-scene-cut-threshold'),
                controller: _sceneCutThreshold,
                label: 'Scene-cut threshold',
                helper: 'Default 0.3. Lower detects more cuts.',
              ),
              _sectionTitle('Faces'),
              _doubleField(
                key: const Key('pref-faces-detect-score'),
                controller: _facesDetectScoreThreshold,
                label: 'Face detect score threshold',
                helper: 'Default 0.2. Local SCRFD score floor.',
              ),
              _intField(
                key: const Key('pref-faces-tray-page-limit'),
                controller: _facesTrayPageLimit,
                label: 'Faces tray fetch limit',
                helper: 'Default 500 (50–500). API appearances page size.',
              ),
              _sectionTitle('Jobs'),
              _intField(
                key: const Key('pref-jobs-poll-interval'),
                controller: _jobsPollIntervalSeconds,
                label: 'Job poll interval (seconds)',
                helper: 'Default 2 (1–30).',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SettingsLeaveChoice { discard, cancel, save }
