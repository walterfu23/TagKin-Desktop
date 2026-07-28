import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/onnx_face_embedder.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Library-wide persons list (D9): named vs unnamed sections.
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
        builder: (_) => SelectableScope(
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

                final persons = snapshot.data!;
                bool isNamed(Person p) =>
                    p.name != null && p.name!.trim().isNotEmpty;
                final named = persons.where(isNamed).toList();
                final unnamed = persons.where((p) => !isNamed(p)).toList();

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

                return ListView(
                  key: const Key('persons-list'),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (named.isNotEmpty) ...[
                      const _SectionHeader(
                        title: 'Named',
                        sectionKey: Key('persons-section-named'),
                      ),
                      for (final person in named)
                        _PersonTile(
                          person: person,
                          onTap: () => _openDetail(person),
                        ),
                    ],
                    if (unnamed.isNotEmpty) ...[
                      const _SectionHeader(
                        title: 'Unnamed',
                        sectionKey: Key('persons-section-unnamed'),
                      ),
                      for (final person in unnamed)
                        _PersonTile(
                          person: person,
                          onTap: () => _openDetail(person),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.sectionKey});

  final String title;
  final Key sectionKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        key: sectionKey,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.person, required this.onTap});

  final Person person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key('person-row-${person.id}'),
      leading: PersonListFaceThumb(personId: person.id),
      title: Text(
        person.name ?? '(unnamed)',
        key: Key('person-name-${person.id}'),
      ),
      subtitle: Text(
        person.id,
        key: Key('person-id-${person.id}'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onTap: onTap,
    );
  }
}
