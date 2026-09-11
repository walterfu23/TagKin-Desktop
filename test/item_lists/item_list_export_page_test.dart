import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_page.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

List<Override> _overrides({
  required FakeItemListsRepository repo,
  ItemListCsvSaver? saveCsv,
}) {
  return [
    itemListsRepositoryProvider.overrideWithValue(repo),
    itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
    if (saveCsv != null) itemListCsvSaverProvider.overrideWithValue(saveCsv),
  ];
}

void main() {
  testWidgets('filter chips, preview, and export use the current row order',
      (tester) async {
    final repo = FakeItemListsRepository(
      facets: const ItemListFacets(
        who: ['Sam'],
        what: ['swimming'],
        where: [],
      ),
      list: ItemList(
        entries: [
          fixtureEntry(itemId: 'photo-a', who: const ['Sam']),
          fixtureEntry(
            itemId: 'video-1',
            kind: ItemListEntryKind.keyperiod,
            keyPeriodId: 'kp-1',
            startMs: 0,
            endMs: 1000,
            who: const ['Sam'],
          ),
        ],
      ),
    );
    String? exported;

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          repo: repo,
          saveCsv: (csv) async {
            exported = csv;
            return '/tmp/item-list.csv';
          },
        ),
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Item list'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Key period'), findsOneWidget);
    expect(find.text('2 rows'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-facet-Who-Sam')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('item-list-preview')));
    await tester.pumpAndSettle();
    expect(repo.lastFilter?.who, ['Sam']);

    await tester.tap(find.byKey(const Key('item-list-export')));
    await tester.pumpAndSettle();
    expect(exported, isNotNull);
    expect(exported, contains('photo-a'));
    expect(exported, contains('kp-1'));
  });

  testWidgets('remove drops a filmstrip tile from the list', (tester) async {
    final repo = FakeItemListsRepository(
      list: ItemList(
        entries: [
          fixtureEntry(itemId: 'photo-a'),
          fixtureEntry(
            itemId: 'video-1',
            kind: ItemListEntryKind.keyperiod,
            keyPeriodId: 'kp-1',
            startMs: 0,
            endMs: 1000,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo: repo),
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 rows'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-remove-photo-a')));
    await tester.pumpAndSettle();
    expect(find.text('1 row'), findsOneWidget);
    expect(find.text('Photo'), findsNothing);
    expect(find.text('Key period'), findsOneWidget);
  });

  testWidgets('many filter chips do not overflow a short viewport',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(800, 400));

    final who = List<String>.generate(40, (i) => 'Person$i');
    final what = List<String>.generate(20, (i) => 'What$i');
    final where = List<String>.generate(20, (i) => 'Where$i');
    final repo = FakeItemListsRepository(
      facets: ItemListFacets(who: who, what: what, where: where),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo: repo),
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('item-list-preview')), findsOneWidget);
    expect(find.byKey(const Key('item-list-count')), findsOneWidget);
  });
}
