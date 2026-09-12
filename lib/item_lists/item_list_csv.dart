import 'package:tagkin_desktop/contract/contract.dart';

/// Inclusive local-day start as UTC ISO for [ItemListFilter.whenFrom].
String itemListWhenFromIso(DateTime localDay) {
  final start = DateTime(localDay.year, localDay.month, localDay.day);
  return start.toUtc().toIso8601String();
}

/// Inclusive local-day end as UTC ISO for [ItemListFilter.whenTo].
String itemListWhenToIso(DateTime localDay) {
  final end = DateTime(
    localDay.year,
    localDay.month,
    localDay.day,
    23,
    59,
    59,
    999,
  );
  return end.toUtc().toIso8601String();
}

/// Display label for an item-list row kind (R2).
String itemListEntryKindLabel(ItemListEntryKind kind) {
  return switch (kind) {
    ItemListEntryKind.photo => 'Photo',
    ItemListEntryKind.keyperiod => 'Key period',
  };
}

/// `m:ss` (or `h:mm:ss`) from a key-period bound in milliseconds.
String formatKeyPeriodMs(int ms) {
  final d = Duration(milliseconds: ms < 0 ? 0 : ms);
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (hours > 0) return '$hours:$minutes:$seconds';
  return '${d.inMinutes}:$seconds';
}
