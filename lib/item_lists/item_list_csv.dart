import 'package:tagkin_desktop/contract/contract.dart';

/// RFC 4180 CSV for an item list (D13). Metadata only — never media bytes.
String itemListToCsv(List<ItemListEntry> entries) {
  final rows = <List<String>>[
    [
      'kind',
      'itemId',
      'keyPeriodId',
      'startMs',
      'endMs',
      'when',
      'who',
      'what',
      'where',
    ],
    for (final e in entries)
      [
        e.kind.wire,
        e.itemId,
        e.keyPeriodId ?? '',
        e.startMs?.toString() ?? '',
        e.endMs?.toString() ?? '',
        e.when ?? '',
        e.who.join('; '),
        e.what.join('; '),
        e.where.join('; '),
      ],
  ];
  return rows.map(_csvRow).join('\r\n') + (rows.isEmpty ? '' : '\r\n');
}

String _csvRow(List<String> fields) => fields.map(_csvField).join(',');

String _csvField(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

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
