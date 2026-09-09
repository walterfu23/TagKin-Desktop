import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_name.dart';

/// Max people rendered in the Faces Set name picker (search or browse).
const int personSearchResultCap = 100;

/// Session MRU of people the user just assigned onto — empty-query shortcut.
const int personPickerRecentCap = 8;

/// Precomputed lowercase name plus word tokens for one [Person].
class IndexedPerson {
  const IndexedPerson({
    required this.person,
    required this.key,
    required this.words,
  });

  final Person person;
  final String key;
  final List<String> words;
}

/// Rank buckets for a non-empty query (exact is strongest).
enum PersonSearchRank { exact, prefix, wordStartOrInitials, substring }

class PersonSearchHit {
  const PersonSearchHit({required this.person, required this.rank});

  final Person person;
  final PersonSearchRank rank;
}

class PersonSearchResult {
  const PersonSearchResult({required this.hits, required this.total});

  final List<PersonSearchHit> hits;
  final int total;

  bool get truncated => hits.length < total;
}

class PersonBrowseSection {
  const PersonBrowseSection({required this.title, required this.persons});

  final String title;
  final List<Person> persons;
}

class PersonBrowseResult {
  const PersonBrowseResult({
    required this.sections,
    required this.total,
    required this.shown,
  });

  final List<PersonBrowseSection> sections;
  final int total;
  final int shown;

  bool get truncated => shown < total;
}

/// Lowercase keys + word tokens. Call once when the picker opens.
List<IndexedPerson> indexPersons(Iterable<Person> persons) {
  return [
    for (final p in persons)
      IndexedPerson(
        person: p,
        key: personNameKey(p.name),
        words: _words(personNameKey(p.name)),
      ),
  ];
}

List<String> _words(String key) => [
  for (final w in key.split(RegExp(r'\s+')))
    if (w.isNotEmpty) w,
];

/// Ranked filter. Empty [query] returns no hits — use [browsePersons] instead.
PersonSearchResult searchPersons({
  required List<IndexedPerson> indexed,
  required String query,
  int cap = personSearchResultCap,
}) {
  final q = personNameKey(query);
  if (q.isEmpty) {
    return const PersonSearchResult(hits: [], total: 0);
  }

  final exact = <IndexedPerson>[];
  final prefix = <IndexedPerson>[];
  final wordOrInitials = <IndexedPerson>[];
  final substring = <IndexedPerson>[];

  for (final p in indexed) {
    if (p.key.isEmpty) continue;
    if (p.key == q) {
      exact.add(p);
    } else if (p.key.startsWith(q)) {
      prefix.add(p);
    } else if (_wordStartOrInitials(p, q)) {
      wordOrInitials.add(p);
    } else if (p.key.contains(q)) {
      substring.add(p);
    }
  }

  void sortBucket(List<IndexedPerson> bucket) {
    bucket.sort((a, b) => comparePersonNames(a.person, b.person));
  }

  sortBucket(exact);
  sortBucket(prefix);
  sortBucket(wordOrInitials);
  sortBucket(substring);

  final ordered = <PersonSearchHit>[
    for (final p in exact)
      PersonSearchHit(person: p.person, rank: PersonSearchRank.exact),
    for (final p in prefix)
      PersonSearchHit(person: p.person, rank: PersonSearchRank.prefix),
    for (final p in wordOrInitials)
      PersonSearchHit(
        person: p.person,
        rank: PersonSearchRank.wordStartOrInitials,
      ),
    for (final p in substring)
      PersonSearchHit(person: p.person, rank: PersonSearchRank.substring),
  ];
  final total = ordered.length;
  final take = cap < 0 ? 0 : cap;
  return PersonSearchResult(
    hits: total <= take ? ordered : ordered.sublist(0, take),
    total: total,
  );
}

bool _wordStartOrInitials(IndexedPerson p, String q) {
  for (final w in p.words) {
    if (w.startsWith(q)) return true;
  }
  if (p.words.length < 2) return false;
  final initials = p.words.map((w) => w[0]).join();
  return initials == q || initials.startsWith(q);
}

/// Empty-query roster: in-folder, then session recents, then everyone else A–Z.
PersonBrowseResult browsePersons({
  required List<IndexedPerson> indexed,
  required List<String> inFolderPersonIds,
  required List<String> recentPersonIds,
  int cap = personSearchResultCap,
}) {
  final byId = <String, Person>{
    for (final p in indexed) p.person.id: p.person,
  };
  final used = <String>{};
  final sections = <PersonBrowseSection>[];
  var remaining = cap < 0 ? 0 : cap;

  List<Person> takeIds(Iterable<String> ids) {
    final out = <Person>[];
    for (final id in ids) {
      if (remaining <= 0) break;
      if (used.contains(id)) continue;
      final person = byId[id];
      if (person == null) continue;
      used.add(id);
      remaining--;
      out.add(person);
    }
    return out;
  }

  final inFolder = takeIds(inFolderPersonIds);
  if (inFolder.isNotEmpty) {
    sections.add(
      PersonBrowseSection(title: 'In this folder', persons: inFolder),
    );
  }
  final recent = takeIds(recentPersonIds);
  if (recent.isNotEmpty) {
    sections.add(
      PersonBrowseSection(title: 'Recently assigned', persons: recent),
    );
  }
  final rest = sortedPersonsByName([
    for (final p in indexed)
      if (!used.contains(p.person.id)) p.person,
  ]);
  final all = remaining <= 0 ? const <Person>[] : rest.take(remaining).toList();
  remaining -= all.length;
  if (all.isNotEmpty) {
    sections.add(PersonBrowseSection(title: 'All people', persons: all));
  }

  return PersonBrowseResult(
    sections: sections,
    total: indexed.length,
    shown: cap < 0 ? 0 : cap - remaining,
  );
}

/// Move [id] to the front of a session MRU, capped.
List<String> rememberRecentPersonId(
  List<String> recent,
  String id, {
  int cap = personPickerRecentCap,
}) {
  final next = [id, for (final x in recent) if (x != id) x];
  if (cap <= 0) return const [];
  return next.length <= cap ? next : next.sublist(0, cap);
}
