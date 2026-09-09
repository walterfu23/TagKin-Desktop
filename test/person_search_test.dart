import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_search.dart';

Person _p(String id, String name) =>
    Person(id: id, name: name, createdAt: '2026-09-08T00:00:00.000Z');

void main() {
  final indexed = indexPersons([
    _p('lisa', 'Lisa'),
    _p('sam', 'Sam'),
    _p('js', 'John Smith'),
    _p('ada', 'Ada'),
    _p('samuel', 'Samuel'),
  ]);

  test('searchPersons ranks exact, prefix, word-start/initials, substring', () {
    final sa = searchPersons(indexed: indexed, query: 'sa');
    expect(
      [for (final h in sa.hits) h.person.id],
      ['sam', 'samuel', 'lisa'],
    );
    expect(sa.hits[0].rank, PersonSearchRank.prefix);
    expect(sa.hits[1].rank, PersonSearchRank.prefix);
    expect(sa.hits.last.rank, PersonSearchRank.substring);

    final exact = searchPersons(indexed: indexed, query: 'SAM');
    expect(exact.hits.first.person.id, 'sam');
    expect(exact.hits.first.rank, PersonSearchRank.exact);
    expect(
      [for (final h in exact.hits) h.person.id],
      ['sam', 'samuel'],
    );
  });

  test('searchPersons matches word-start and initials', () {
    final smith = searchPersons(indexed: indexed, query: 'sm');
    expect(smith.hits.single.person.id, 'js');
    expect(smith.hits.single.rank, PersonSearchRank.wordStartOrInitials);

    final initials = searchPersons(indexed: indexed, query: 'js');
    expect(initials.hits.single.person.id, 'js');
    expect(initials.hits.single.rank, PersonSearchRank.wordStartOrInitials);
  });

  test('searchPersons caps hits and reports total', () {
    final many = indexPersons([
      for (var i = 0; i < 150; i++)
        _p('p$i', 'Person ${i.toString().padLeft(3, '0')}'),
    ]);
    final result = searchPersons(indexed: many, query: 'person', cap: 100);
    expect(result.hits, hasLength(100));
    expect(result.total, 150);
    expect(result.truncated, isTrue);
    expect(result.hits.first.person.name, 'Person 000');
    expect(result.hits.last.person.name, 'Person 099');
  });

  test('browsePersons shows in-folder, recents, then A–Z under the cap', () {
    final browse = browsePersons(
      indexed: indexed,
      inFolderPersonIds: const ['sam'],
      recentPersonIds: const ['lisa', 'sam'],
      cap: 4,
    );
    expect(browse.sections.map((s) => s.title).toList(), [
      'In this folder',
      'Recently assigned',
      'All people',
    ]);
    expect(browse.sections[0].persons.single.id, 'sam');
    expect(browse.sections[1].persons.single.id, 'lisa');
    expect(
      [for (final p in browse.sections[2].persons) p.id],
      ['ada', 'js'],
    );
    expect(browse.shown, 4);
    expect(browse.total, 5);
    expect(browse.truncated, isTrue);
  });

  test('rememberRecentPersonId moves id to front and caps', () {
    expect(rememberRecentPersonId(const [], 'a'), ['a']);
    expect(rememberRecentPersonId(const ['a', 'b'], 'b'), ['b', 'a']);
    expect(
      rememberRecentPersonId(
        const ['a', 'b', 'c'],
        'd',
        cap: 3,
      ),
      ['d', 'a', 'b'],
    );
  });
}
