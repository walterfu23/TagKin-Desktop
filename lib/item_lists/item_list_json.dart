import 'dart:convert';

import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

/// Pretty-printed item-list JSON (D13). Metadata and local paths only — never
/// media bytes (R1).
String itemListToJson({
  required List<ItemListEntry> entries,
  required Map<String, Item> itemsById,
  ItemListFilter? filters,
  String description = '',
  required DateTime exportedAt,
}) {
  final doc = <String, Object?>{
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'description': description,
    'filters': {
      'who': filters?.who ?? const <String>[],
      'what': filters?.what ?? const <String>[],
      'where': filters?.where ?? const <String>[],
      'whenFrom': filters?.whenFrom,
      'whenTo': filters?.whenTo,
    },
    'entries': [
      for (final e in entries)
        {
          'kind': e.kind.wire,
          'path': localPathFromSourceRef(itemsById[e.itemId]?.sourceRef),
          'itemId': e.itemId,
          'keyPeriodId': e.keyPeriodId,
          'startMs': e.startMs,
          'endMs': e.endMs,
          'when': e.when,
          'who': e.who,
          'what': e.what,
          'where': e.where,
        },
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(doc);
}
