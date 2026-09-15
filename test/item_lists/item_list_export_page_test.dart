import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_page.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

import '../fake_comments_repository.dart';
import '../fake_items_repository.dart';
import '../fake_persons_repository.dart';

List<Override> _overrides({
  ItemListJsonSaver? saveJson,
  FakeItemsRepository? items,
  FakePersonsRepository? persons,
  CollectionsStore? collections,
}) {
  return [
    itemsRepositoryProvider.overrideWithValue(items ?? FakeItemsRepository()),
    commentsRepositoryProvider.overrideWithValue(FakeCommentsRepository()),
    personsRepositoryProvider.overrideWithValue(
      persons ?? FakePersonsRepository(),
    ),
    collectionsStoreProvider.overrideWithValue(
      collections ?? MemoryCollectionsStore(),
    ),
    if (saveJson != null) itemListJsonSaverProvider.overrideWithValue(saveJson),
  ];
}

Future<void> _pumpPage(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: const MaterialApp(
        home: SelectableScope(child: ItemListExportPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('views dropdown, stills, and export use the current row order',
      (tester) async {
    String? exported;
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'photo-a', sourceRef: ''),
            fixtureItem(id: 'photo-b', sourceRef: ''),
          ],
        ),
        saveJson: (json) async {
          exported = json;
          return '/tmp/item-list.json';
        },
      ),
    );

    expect(find.text('Item list'), findsOneWidget);
    expect(find.text('Photo'), findsNWidgets(2));
    expect(find.text('2 items'), findsOneWidget);
    expect(find.byKey(const Key('item-list-views-menu')), findsOneWidget);
    expect(find.byKey(const Key('item-list-export')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byKey(const Key('item-list-export')),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('item-list-drag-photo-photo-a')), findsOneWidget);
    expect(find.byKey(const Key('item-hover-preview-photo-a')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('item-list-description')),
      'Beach weekend',
    );
    await tester.tap(find.byKey(const Key('item-list-export')));
    await tester.pumpAndSettle();
    expect(exported, isNotNull);
    expect(exported, contains('photo-a'));
    expect(exported, contains('photo-b'));
    expect(exported, contains('Beach weekend'));
  });

  testWidgets('remove drops a filmstrip tile from the list', (tester) async {
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'photo-a', sourceRef: ''),
            fixtureItem(id: 'photo-b', sourceRef: ''),
          ],
        ),
      ),
    );
    expect(find.text('2 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-remove-photo-photo-a')));
    await tester.pumpAndSettle();
    expect(find.text('1 item'), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-photo-photo-a')), findsNothing);
    expect(find.byKey(const Key('item-list-drag-photo-photo-b')), findsOneWidget);
  });

  testWidgets('selecting a view shows only that view’s items', (tester) async {
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'c1',
            name: 'Trip',
            leafFolders: [],
            views: [
              SavedView(
                id: 'v-keep',
                name: 'Keep',
                filters: LibraryViewFilters(filterQuery: 'keep'),
              ),
            ],
          ),
        ],
        currentCollectionId: 'c1',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: _overrides(
          items: FakeItemsRepository(
            items: [
              fixtureItem(id: 'keep', sourceRef: 'keep'),
              fixtureItem(id: 'drop', sourceRef: 'other'),
            ],
          ),
          collections: store,
        ),
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(ItemListExportPage));
    await ProviderScope.containerOf(ctx)
        .read(collectionsControllerProvider)
        .bootstrapSession(const []);
    await tester.pumpAndSettle();

    expect(find.text('2 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-views-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-views-v-keep')));
    await tester.pumpAndSettle();

    expect(find.text('1 item'), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-photo-keep')), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-photo-drop')), findsNothing);
    expect(find.text('Keep'), findsWidgets);
  });

  testWidgets('opens on the Folders current view', (tester) async {
    const keepView = SavedView(
      id: 'v-keep',
      name: 'Keep',
      filters: LibraryViewFilters(filterQuery: 'keep'),
    );
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'c1',
            name: 'Trip',
            leafFolders: [],
            views: [keepView],
          ),
        ],
        currentCollectionId: 'c1',
      ),
    );
    final container = ProviderContainer(
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'keep', sourceRef: 'keep'),
            fixtureItem(id: 'drop', sourceRef: 'other'),
          ],
        ),
        collections: store,
      ),
    );
    addTearDown(container.dispose);

    await container
        .read(collectionsControllerProvider)
        .bootstrapSession(const []);
    container.read(libraryTableControllerProvider).setActiveView(
          keepView.id,
          keepView.filters,
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1 item'), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-photo-keep')), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-photo-drop')), findsNothing);
    expect(find.text('Keep'), findsWidgets);
  });

  testWidgets('Export tiles show stored sharpness when the pref is on',
      (tester) async {
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'sharp', sharpness: 8583, sourceRef: ''),
            fixtureItem(id: 'blurry', sharpness: 5, sourceRef: ''),
          ],
        ),
      ),
    );
    expect(
      find.byKey(const Key('item-list-sharpness-photo-sharp')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('item-list-sharpness-photo-blurry')),
      findsOneWidget,
    );
    expect(find.text('8583'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('Export tiles omit sharpness when the pref is off',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(
            items: FakeItemsRepository(
              items: [fixtureItem(id: 'sharp', sharpness: 8583, sourceRef: '')],
            ),
          ),
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
    expect(
      find.byKey(const Key('item-list-sharpness-photo-sharp')),
      findsNothing,
    );
    expect(find.text('8583'), findsNothing);
  });

  testWidgets('Format menu exports FCP7 XML and FCPXML', (tester) async {
    String? exported;
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'photo-a', sourceRef: ''),
          ],
        ),
        saveJson: (json) async {
          exported = json;
          return '/tmp/item-list.out';
        },
      ),
    );

    expect(find.byKey(const Key('item-list-format-menu')), findsOneWidget);
    expect(find.text('JSON'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-format-fcp7Xml')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-export')));
    await tester.pumpAndSettle();
    expect(exported, contains('<xmeml version="4">'));

    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-format-fcpxml')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-export')));
    await tester.pumpAndSettle();
    expect(exported, contains('<fcpxml version="1.9">'));
  });

  testWidgets('MP4 format shows generate music, not a vendor name',
      (tester) async {
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'photo-a', sourceRef: ''),
          ],
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    expect(find.text('MP4 (with music)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-format-mp4WithMusic')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-music-prompt')), findsOneWidget);
    expect(find.byKey(const Key('item-list-generate-music')), findsOneWidget);
    expect(find.textContaining('Eleven'), findsNothing);

    expect(find.byKey(const Key('item-list-music-prompt-preset')), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-music-prompt-preset')));
    await tester.pumpAndSettle();
    expect(find.text('Warm family'), findsOneWidget);
    await tester.tap(find.text('Warm family'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('item-list-music-prompt')),
    );
    expect(field.controller?.text, contains('Instrumental only'));
  });
}
