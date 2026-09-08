/// Case-insensitive alphabetical order for a user-visible list label.
///
/// Equal-ignoring-case labels keep a stable original-string tiebreak so the
/// list does not jitter between equal spellings.
int compareLabelsAlpha(String a, String b) {
  final ci = a.trim().toLowerCase().compareTo(b.trim().toLowerCase());
  return ci != 0 ? ci : a.compareTo(b);
}

/// Copy of [items] sorted by [label] via [compareLabelsAlpha].
List<T> sortedAlphaBy<T>(Iterable<T> items, String Function(T) label) =>
    List<T>.from(items)..sort((a, b) => compareLabelsAlpha(label(a), label(b)));
