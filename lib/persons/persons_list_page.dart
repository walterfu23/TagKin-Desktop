import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/link_state_view.dart';
import 'package:tagkin_desktop/persons/person_detail_page.dart';

/// Library-wide persons list (D9): suggested vs confirmed sections.
///
/// Never displays likeness vectors (R1). Labels use canonical "person" (R2).
class PersonsListPage extends ConsumerStatefulWidget {
  const PersonsListPage({super.key});

  @override
  ConsumerState<PersonsListPage> createState() => _PersonsListPageState();
}

class _PersonsListPageState extends ConsumerState<PersonsListPage> {
  late Future<List<Person>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Person>> _load() {
    return ref.read(personsRepositoryProvider).listPersons();
  }

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _openDetail(Person person) async {
    final container = ProviderScope.containerOf(context);
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => UncontrolledProviderScope(
          container: container,
          child: PersonDetailPage(personId: person.id),
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
      body: FutureBuilder<List<Person>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(key: Key('persons-loading')),
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
          final suggested = persons
              .where((p) => p.linkState == LinkState.suggested)
              .toList();
          final confirmed = persons
              .where((p) => p.linkState == LinkState.confirmed)
              .toList();

          if (persons.isEmpty) {
            return const Center(
              child: Text(
                'No persons yet — run Find person matches on an item.',
                key: Key('persons-empty'),
                textAlign: TextAlign.center,
              ),
            );
          }

          return ListView(
            key: const Key('persons-list'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              if (suggested.isNotEmpty) ...[
                const _SectionHeader(
                  title: 'Suggested',
                  sectionKey: Key('persons-section-suggested'),
                ),
                for (final person in suggested)
                  _PersonTile(
                    person: person,
                    onTap: () => _openDetail(person),
                  ),
              ],
              if (confirmed.isNotEmpty) ...[
                const _SectionHeader(
                  title: 'Confirmed',
                  sectionKey: Key('persons-section-confirmed'),
                ),
                for (final person in confirmed)
                  _PersonTile(
                    person: person,
                    onTap: () => _openDetail(person),
                  ),
              ],
            ],
          );
        },
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
      title: Text(
        person.name ?? '(unnamed)',
        key: Key('person-name-${person.id}'),
      ),
      subtitle: Text(
        person.id,
        key: Key('person-id-${person.id}'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      trailing: LinkStateBadge(linkState: person.linkState),
      onTap: onTap,
    );
  }
}
