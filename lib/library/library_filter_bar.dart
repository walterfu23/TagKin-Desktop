import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/library/folders_undo_recorder.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';

/// Folders filter strip under the toolbar: captured-date range, how many
/// filters are narrowing the table, and Clear filters. Who / What / Where
/// are filtered from their column headers; the text box above matches any
/// column (including comments and source).
class LibraryFilterBar extends ConsumerWidget {
  const LibraryFilterBar({super.key, required this.table});

  final LibraryTableController table;

  static String formatDay(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year.toString().padLeft(4, '0')}-${two(d.month)}-${two(d.day)}';
  }

  Future<void> _record(
    WidgetRef ref,
    String label,
    Future<void> Function() mutate,
  ) {
    return ref
        .read(foldersUndoProvider)
        .record(
          table: table,
          cols: ref.read(collectionsControllerProvider),
          label: label,
          mutate: mutate,
        );
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required bool isFrom,
  }) async {
    final current = isFrom ? table.capturedFrom : table.capturedTo;
    final initial =
        (current == null ? null : DateTime.tryParse(current)) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
      helpText: isFrom ? 'Captured from' : 'Captured to',
    );
    if (picked == null) return;
    final day = formatDay(picked);
    await _record(ref, 'Filter date', () async {
      table.setCapturedRange(
        from: isFrom ? day : table.capturedFrom,
        to: isFrom ? table.capturedTo : day,
      );
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final from = table.capturedFrom;
    final to = table.capturedTo;
    final count = table.activeFilterCount;
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          const Text('Captured'),
          OutlinedButton(
            key: const Key('library-date-from'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => unawaited(_pick(context, ref, isFrom: true)),
            child: Text(from == null ? 'From: any' : 'From: $from'),
          ),
          OutlinedButton(
            key: const Key('library-date-to'),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => unawaited(_pick(context, ref, isFrom: false)),
            child: Text(to == null ? 'To: any' : 'To: $to'),
          ),
          if (from != null || to != null)
            IconButton(
              key: const Key('library-date-clear'),
              tooltip: 'Clear date range',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 16),
              onPressed: () => unawaited(
                _record(ref, 'Clear date range', () async {
                  table.setCapturedRange();
                }),
              ),
            ),
          const SizedBox(width: 8),
          TextButton(
            key: const Key('library-clear-filters'),
            onPressed: table.hasActiveFilters
                ? () => unawaited(
                    _record(ref, 'Clear filters', table.clearFilters),
                  )
                : null,
            child: const Text('Clear filters'),
          ),
          if (count > 0)
            Text(
              key: const Key('library-active-filters'),
              count == 1 ? '1 filter active' : '$count filters active',
            ),
        ],
      ),
    );
  }
}
