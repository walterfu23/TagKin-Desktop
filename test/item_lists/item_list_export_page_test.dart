import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_page.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

import '../fake_items_repository.dart';
import '../fake_persons_repository.dart';
import 'fake_item_lists_repository.dart';

List<Override> _overrides({
  required FakeItemListsRepository repo,
  ItemListJsonSaver? saveJson,
  FakeItemsRepository? items,
  FakePersonsRepository? persons,
}) {
  return [
    itemListsRepositoryProvider.overrideWithValue(repo),
    itemsRepositoryProvider.overrideWithValue(items ?? FakeItemsRepository()),
    personsRepositoryProvider.overrideWithValue(
      persons ?? FakePersonsRepository(),
    ),
    if (saveJson != null) itemListJsonSaverProvider.overrideWithValue(saveJson),
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
          saveJson: (json) async {
            exported = json;
            return '/tmp/item-list.json';
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
    expect(find.text('2 items'), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-photo-a')), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-kp-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-facet-Who-Sam')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('item-list-preview')));
    await tester.pumpAndSettle();
    expect(repo.lastFilter?.who, ['Sam']);

    await tester.enterText(
      find.byKey(const Key('item-list-description')),
      'Beach weekend',
    );
    await tester.tap(find.byKey(const Key('item-list-export')));
    await tester.pumpAndSettle();
    expect(exported, isNotNull);
    expect(exported, contains('photo-a'));
    expect(exported, contains('kp-1'));
    expect(exported, contains('Beach weekend'));
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
    expect(find.text('2 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-remove-photo-a')));
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
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

  testWidgets('selected Who draws unlabeled face boxes on stills',
      (tester) async {
    const region = TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.5, xMax: 0.5);
    final item = fixtureItem(id: 'photo-a');
    final repo = FakeItemListsRepository(
      facets: const ItemListFacets(who: ['Sam'], what: [], where: []),
      list: ItemList(
        entries: [fixtureEntry(itemId: 'photo-a', who: const ['Sam'])],
      ),
    );
    final items = FakeItemsRepository(
      knowledgeByItemId: {
        'photo-a': fixtureKnowledge(
          item: item,
          appearances: [
            fixtureAppearance(
              id: 'ap_sam',
              personId: 'p1',
              itemId: 'photo-a',
              region: region,
            ),
          ],
        ),
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          repo: repo,
          items: items,
          persons: FakePersonsRepository(
            persons: [fixturePersonDetail(id: 'p1', name: 'Sam')],
          ),
        ),
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-list-face-ap_sam')), findsNothing);

    await tester.tap(find.byKey(const Key('item-list-facet-Who-Sam')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-face-ap_sam')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('Hide blurry toggle hides low-sharpness photos', (tester) async {
    final repo = FakeItemListsRepository(
      list: ItemList(
        entries: [
          fixtureEntry(itemId: 'sharp'),
          fixtureEntry(itemId: 'blurry'),
        ],
      ),
    );
    final items = FakeItemsRepository(
      items: [
        fixtureItem(id: 'sharp', sharpness: 400, sourceRef: ''),
        fixtureItem(id: 'blurry', sharpness: 5, sourceRef: ''),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo: repo, items: items),
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('hide-blurry-switch')));
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-blurry')), findsNothing);
    expect(find.byKey(const Key('item-list-drag-sharp')), findsOneWidget);

    // Flipping back off restores the hidden tile without re-Preview.
    await tester.tap(find.byKey(const Key('hide-blurry-switch')));
    await tester.pumpAndSettle();
    expect(find.text('2 items'), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-blurry')), findsOneWidget);
  });

  testWidgets('Export excludes hidden photos while Hide blurry is on',
      (tester) async {
    final repo = FakeItemListsRepository(
      list: ItemList(
        entries: [
          fixtureEntry(itemId: 'sharp'),
          fixtureEntry(itemId: 'blurry'),
        ],
      ),
    );
    final items = FakeItemsRepository(
      items: [
        fixtureItem(id: 'sharp', sharpness: 400, sourceRef: ''),
        fixtureItem(id: 'blurry', sharpness: 5, sourceRef: ''),
      ],
    );
    String? exported;

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          repo: repo,
          items: items,
          saveJson: (json) async {
            exported = json;
            return '/tmp/item-list.json';
          },
        ),
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('hide-blurry-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-export')));
    await tester.pumpAndSettle();

    expect(exported, isNotNull);
    expect(exported, contains('sharp'));
    expect(exported, isNot(contains('blurry')));
  });

  testWidgets('Export tiles show stored sharpness when the pref is on',
      (tester) async {
    final repo = FakeItemListsRepository(
      list: ItemList(
        entries: [
          fixtureEntry(itemId: 'sharp'),
          fixtureEntry(itemId: 'blurry'),
        ],
      ),
    );
    final items = FakeItemsRepository(
      items: [
        fixtureItem(id: 'sharp', sharpness: 8583, sourceRef: ''),
        fixtureItem(id: 'blurry', sharpness: 5, sourceRef: ''),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(repo: repo, items: items),
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-sharpness-sharp')), findsOneWidget);
    expect(find.byKey(const Key('item-list-sharpness-blurry')), findsOneWidget);
    expect(find.text('8583'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('Export tiles omit sharpness when the pref is off',
      (tester) async {
    final repo = FakeItemListsRepository(
      list: ItemList(
        entries: [fixtureEntry(itemId: 'sharp')],
      ),
    );
    final items = FakeItemsRepository(
      items: [fixtureItem(id: 'sharp', sharpness: 8583, sourceRef: '')],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(repo: repo, items: items),
          desktopPrefsProvider.overrideWithValue(
            const DesktopPrefs(showSharpnessScores: false),
          ),
        ],
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-sharpness-sharp')), findsNothing);
    expect(find.text('8583'), findsNothing);
  });
}
