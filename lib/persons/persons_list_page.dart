import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';
import 'package:tagkin_desktop/persons/person_name.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/onnx_face_embedder.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';

/// Library-wide persons list (D9). Every person is always named (R2) — the
/// old "Unnamed" section is gone; unassigned likeness lives in FaceGroup
/// FA/FM in the Faces trays instead.
///
/// Never displays likeness vectors (R1). Labels use canonical "person" (R2).
class PersonsListPage extends ConsumerStatefulWidget {
  const PersonsListPage({super.key});

  @override
  ConsumerState<PersonsListPage> createState() => _PersonsListPageState();
}

class _PersonsListPageState extends ConsumerState<PersonsListPage> {
  late Future<List<Person>> _future;
  bool _modelsMissing = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _modelsMissing = !FaceModelPaths.recogModelAvailable();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (consumeFaceEmbedderStubNotice()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            key: Key('face-embedder-stub-notice'),
            content: Text(
              'Face models missing — likeness linking skipped. '
              'Run mac/117_fetch_face_models.sh, restart the app, then re-analyze.',
            ),
            duration: Duration(seconds: 8),
          ),
        );
      }
    });
  }

  Future<List<Person>> _load() {
    return ref.read(personsRepositoryProvider).listPersons();
  }

  void _retry() {
    setState(() {
      _modelsMissing = !FaceModelPaths.recogModelAvailable();
      _future = _load();
    });
  }

  Future<void> _openDetail(Person person) async {
    final container = ProviderScope.containerOf(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UndoSelectableRoute(
          child: UncontrolledProviderScope(
            container: container,
            child: PersonDetailPage(personId: person.id),
          ),
        ),
      ),
    );
    if (mounted) _retry();
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps this page mounted; reload when returning from Faces.
    ref.listen<TopLevelTab>(activeTopLevelTabProvider, (previous, next) {
      if (next == TopLevelTab.persons && previous != next) {
        _retry();
      }
    });
    final columns = ref.watch(desktopPrefsProvider).personsListColumns.clamp(
          DesktopPrefs.personsListColumnsMin,
          DesktopPrefs.personsListColumnsMax,
        );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Persons'),
      ),
      body: Column(
        children: [
          if (_modelsMissing)
            MaterialBanner(
              key: const Key('persons-models-missing-banner'),
              content: const Text(
                'Face models not found — cross-photo person linking is off. '
                'Run mac/117_fetch_face_models.sh (or win equivalent), restart, '
                'then re-analyze photos.',
              ),
              actions: [
                TextButton(
                  key: const Key('persons-models-missing-dismiss'),
                  onPressed: () => setState(() => _modelsMissing = false),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          Expanded(
            child: FutureBuilder<List<Person>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(
                    child: CircularProgressIndicator(
                      key: Key('persons-loading'),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  final error = snapshot.error!;
                  final isNotFound =
                      error is ApiException && error.statusCode == 404;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isNotFound
                                ? 'Persons not found'
                                : 'Could not load persons: $error',
                            key: isNotFound
                                ? const Key('persons-not-found')
                                : const Key('persons-error'),
                            textAlign: TextAlign.center,
                          ),
                          if (!isNotFound) ...[
                            const SizedBox(height: 16),
                            FilledButton(
                              key: const Key('persons-retry'),
                              onPressed: _retry,
                              child: const Text('Retry'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                final persons = List<Person>.from(snapshot.data!)
                  ..sort((a, b) {
                    final byName = personNameKey(a.name)
                        .compareTo(personNameKey(b.name));
                    if (byName != 0) return byName;
                    return a.id.compareTo(b.id);
                  });

                if (persons.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _modelsMissing
                            ? 'No persons yet — install face models, restart, '
                                'and re-analyze photos that have who face boxes.'
                            : 'No persons yet — analyze photos with who face '
                                'boxes so likeness can link across items.',
                        key: const Key('persons-empty'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return GridView.builder(
                  key: const Key('persons-list'),
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.75,
                  ),
                  itemCount: persons.length,
                  itemBuilder: (context, index) {
                    final person = persons[index];
                    return _PersonCell(
                      person: person,
                      onTap: () => _openDetail(person),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PersonCell extends StatelessWidget {
  const _PersonCell({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: Key('person-row-${person.id}'),
      onTap: onTap,
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final side = constraints.maxWidth < constraints.maxHeight
                    ? constraints.maxWidth
                    : constraints.maxHeight;
                return Center(
                  child: PersonListFaceThumb(
                    personId: person.id,
                    size: side.clamp(32.0, 240.0),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            person.name,
            key: Key('person-name-${person.id}'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
