import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart' hide ItemListExportFormat;
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_page.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';
import 'package:tagkin_desktop/item_lists/item_list_music.dart';
import 'package:tagkin_desktop/item_lists/item_list_navigation.dart';
import 'package:tagkin_desktop/item_lists/item_list_slideshow_preview.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_store.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

import '../fake_comments_repository.dart';
import '../fake_items_repository.dart';
import '../fake_persons_repository.dart';
import 'fake_item_lists_repository.dart';

class FakeMusicRepository extends MusicRepository {
  FakeMusicRepository()
      : super(
          ApiClient(
            baseUrl: 'http://music.test',
            tokenProvider: () => 'tok',
          ),
        );

  int generateCount = 0;
  final List<String> writtenPaths = [];
  final List<List<String>?> avoidHistory = [];

  @override
  Future<EstimateMusicResponse> estimate({required int durationMs}) async {
    return const EstimateMusicResponse(creditsUsed: 0);
  }

  @override
  Future<GenerateMusicResponse> generate({
    required int durationMs,
    required String prompt,
    List<String>? avoidSoundtrackIds,
  }) async {
    generateCount++;
    avoidHistory.add(avoidSoundtrackIds);
    return GenerateMusicResponse(
      audioBase64: base64Encode([generateCount]),
      mimeType: 'audio/wav',
      generatedMs: durationMs,
      creditsUsed: 0,
      soundtrackId: 'take-$generateCount',
    );
  }

  @override
  Future<File> writeAudioTemp(GenerateMusicResponse generated) async {
    writtenPaths.add('take-$generateCount.wav');
    return File(writtenPaths.last);
  }
}

List<Override> _overrides({
  ItemListJsonSaver? saveJson,
  FakeItemsRepository? items,
  FakePersonsRepository? persons,
  CollectionsStore? collections,
  MusicRepository? music,
  DesktopPrefsController? prefs,
}) {
  return [
    itemsRepositoryProvider.overrideWithValue(items ?? FakeItemsRepository()),
    commentsRepositoryProvider.overrideWithValue(FakeCommentsRepository()),
    personsRepositoryProvider.overrideWithValue(
      persons ?? FakePersonsRepository(),
    ),
    itemListsRepositoryProvider.overrideWithValue(FakeItemListsRepository()),
    collectionsStoreProvider.overrideWithValue(
      collections ?? MemoryCollectionsStore(),
    ),
    if (saveJson != null) itemListJsonSaverProvider.overrideWithValue(saveJson),
    if (music != null) musicRepositoryProvider.overrideWithValue(music),
    if (prefs != null)
      desktopPrefsControllerProvider.overrideWith((ref) => prefs),
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

Future<void> _pumpExportOnStack(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                key: const Key('open-export'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ItemListExportPage(),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-export')));
  await tester.pumpAndSettle();
}

void main() {
  setUp(resetItemListExportBusyLeave);
  tearDown(resetItemListExportBusyLeave);

  test('appExitCanSkipLeavePrompt is false when export is busy', () {
    expect(
      appExitCanSkipLeavePrompt(
        collectionDirty: false,
        viewDirty: false,
        exportBusy: false,
      ),
      isTrue,
    );
    expect(
      appExitCanSkipLeavePrompt(
        collectionDirty: false,
        viewDirty: false,
        exportBusy: true,
      ),
      isFalse,
    );
    expect(
      appExitCanSkipLeavePrompt(
        collectionDirty: true,
        viewDirty: false,
        exportBusy: false,
      ),
      isFalse,
    );
  });

  test('itemListLeaveBusyBody names encode and music generate', () {
    expect(
      itemListLeaveBusyBody(encoding: false, generatingMusic: false),
      isNull,
    );
    expect(
      itemListLeaveBusyBody(encoding: true, generatingMusic: false),
      contains('still encoding'),
    );
    expect(
      itemListLeaveBusyBody(encoding: false, generatingMusic: true),
      contains('still generating'),
    );
  });

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
    final folders = container.read(libraryTableControllerProvider);
    folders.setActiveView(keepView.id, keepView.filters);
    await folders.applyLibraryViewFilters(keepView.filters);

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

  testWidgets(
    'opens on dirty View01 Hide folder using Folders live filters',
    (tester) async {
      const trip = 'albums/Trip';
      const view01 = SavedView(
        id: 'v-view01',
        name: 'View01',
        filters: LibraryViewFilters(),
      );
      final store = MemoryCollectionsStore(
        const CollectionsFile(
          collections: [
            Collection(
              id: 'c1',
              name: 'Trip',
              leafFolders: [],
              views: [view01],
            ),
          ],
          currentCollectionId: 'c1',
        ),
      );
      final container = ProviderContainer(
        overrides: _overrides(
          items: FakeItemsRepository(
            items: [
              fixtureItem(
                id: 'hidden-folder',
                sourceRef: 'albums/Trip/a.jpg',
              ),
              fixtureItem(id: 'keep', sourceRef: 'albums/Other/b.jpg'),
            ],
          ),
          collections: store,
        ),
      );
      addTearDown(container.dispose);

      await container
          .read(collectionsControllerProvider)
          .bootstrapSession(const []);
      final folders = container.read(libraryTableControllerProvider);
      folders.setActiveView(view01.id, view01.filters);
      await folders.applyLibraryViewFilters(view01.filters);
      folders.setFolderHidden(trip, hidden: true);

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
      expect(
        find.byKey(const Key('item-list-drag-photo-hidden-folder')),
        findsNothing,
      );
      expect(find.text('View01'), findsWidgets);
    },
  );

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
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

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

  testWidgets('Try another keeps takes and switching chips changes preview',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final music = FakeMusicRepository();
    final prefs = DesktopPrefsController(store: _MemoryDesktopPrefsStore());

    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'photo-a', sourceRef: ''),
            fixtureItem(id: 'photo-b', sourceRef: ''),
          ],
        ),
        music: music,
        prefs: prefs,
      ),
    );

    expect(find.text('2 items'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-format-mp4WithMusic')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('item-list-music-prompt')),
      'quiet piano',
    );
    await tester.pump();

    final generateBtn = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('item-list-generate-music')),
    );
    expect(generateBtn.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('item-list-generate-music')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('item-list-generate-music-dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('item-list-generate-music-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-music-error')), findsNothing);

    expect(music.generateCount, 1);
    expect(music.writtenPaths, hasLength(1));
    expect(music.avoidHistory.single, isEmpty);
    expect(find.text('Try another'), findsOneWidget);
    expect(find.byKey(const Key('item-list-music-takes')), findsNothing);
    expect(find.byType(ItemListSlideshowPreview), findsOneWidget);
    expect(
      tester
          .widget<ItemListSlideshowPreview>(
            find.byType(ItemListSlideshowPreview),
          )
          .audioPath,
      music.writtenPaths[0],
    );

    await tester.tap(find.byKey(const Key('item-list-generate-music')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-generate-music-confirm')));
    await tester.pumpAndSettle();

    expect(music.generateCount, 2);
    expect(music.avoidHistory[1], ['take-1']);
    expect(find.byKey(const Key('item-list-music-take-0')), findsOneWidget);
    expect(find.byKey(const Key('item-list-music-take-1')), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('item-list-music-take-0')))
          .selected,
      isFalse,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('item-list-music-take-1')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ItemListSlideshowPreview>(
            find.byType(ItemListSlideshowPreview),
          )
          .audioPath,
      music.writtenPaths[1],
    );

    await tester.tap(find.byKey(const Key('item-list-music-take-0')));
    await tester.pumpAndSettle();
    expect(music.generateCount, 2);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('item-list-music-take-0')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<ItemListSlideshowPreview>(
            find.byType(ItemListSlideshowPreview),
          )
          .audioPath,
      music.writtenPaths[0],
    );
  });

  testWidgets('Export shows Exporting… until save finishes', (tester) async {
    final gate = Completer<String?>();
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'photo-a', sourceRef: ''),
            fixtureItem(id: 'photo-b', sourceRef: ''),
          ],
        ),
        saveJson: (json) => gate.future,
      ),
    );

    await tester.tap(find.byKey(const Key('item-list-export')));
    await tester.pump();
    expect(find.text('Exporting…'), findsOneWidget);

    gate.complete('/tmp/item-list.json');
    await tester.pumpAndSettle();
    expect(find.text('Exporting…'), findsNothing);
    expect(find.text('Saved /tmp/item-list.json'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Saved /tmp/item-list.json'), findsNothing);
  });

  testWidgets('MP4 export shows encode phase status', (tester) async {
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
      ),
    );

    final ctx = tester.element(find.byType(ItemListExportPage));
    final controller = ProviderScope.containerOf(ctx)
        .read(itemListExportControllerProvider);

    controller.mp4Phase = ItemListMp4Phase.staging;
    controller.notifyListeners();
    await tester.pump();
    expect(find.byKey(const Key('item-list-mp4-phase')), findsOneWidget);
    expect(find.text('Preparing files…'), findsOneWidget);

    controller.mp4Phase = ItemListMp4Phase.encodingClips;
    controller.mp4ClipIndex = 1;
    controller.mp4ClipCount = 2;
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Encoding clip 1 of 2…'), findsOneWidget);

    controller.mp4Phase = ItemListMp4Phase.assembling;
    controller.mp4ClipIndex = null;
    controller.mp4ClipCount = null;
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Composing video…'), findsOneWidget);

    controller.mp4Phase = ItemListMp4Phase.writingOut;
    controller.notifyListeners();
    await tester.pump();
    expect(find.text('Writing file…'), findsOneWidget);

    controller.mp4Phase = null;
    controller.notifyListeners();
    await tester.pump();
    expect(find.byKey(const Key('item-list-mp4-phase')), findsNothing);
  });

  testWidgets('Stay keeps Export list while encoding', (tester) async {
    await _pumpExportOnStack(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
      ),
    );
    final ctx = tester.element(find.byType(ItemListExportPage));
    final controller = ProviderScope.containerOf(ctx)
        .read(itemListExportControllerProvider);
    controller.mp4Phase = ItemListMp4Phase.encodingClips;
    controller.notifyListeners();
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-leave-encoding-dialog')), findsOneWidget);
    expect(find.textContaining('still encoding'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-leave-stay')));
    await tester.pumpAndSettle();
    expect(find.byType(ItemListExportPage), findsOneWidget);
  });

  testWidgets('Leave pops Export list while encoding', (tester) async {
    await _pumpExportOnStack(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
      ),
    );
    final ctx = tester.element(find.byType(ItemListExportPage));
    final controller = ProviderScope.containerOf(ctx)
        .read(itemListExportControllerProvider);
    controller.mp4Phase = ItemListMp4Phase.assembling;
    controller.notifyListeners();
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav-folders')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-leave-encoding-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-leave-leave')));
    await tester.pumpAndSettle();
    expect(find.byType(ItemListExportPage), findsNothing);
    expect(find.byKey(const Key('open-export')), findsOneWidget);
  });

  testWidgets('leave dialog uses music copy when generating', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () {
              unawaited(
                confirmLeaveItemListBusy(
                  context: ctx,
                  encoding: false,
                  generatingMusic: true,
                ),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-leave-encoding-dialog')), findsOneWidget);
    expect(find.textContaining('still generating'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-leave-stay')));
    await tester.pumpAndSettle();
  });

  testWidgets('Export page registers quit-gate busy while encoding',
      (tester) async {
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
      ),
    );
    expect(itemListConfirmLeaveIfBusy, isNotNull);
    expect(itemListExportBusy, isFalse);

    final ctx = tester.element(find.byType(ItemListExportPage));
    final controller = ProviderScope.containerOf(ctx)
        .read(itemListExportControllerProvider);
    controller.mp4Phase = ItemListMp4Phase.encodingClips;
    controller.notifyListeners();
    await tester.pump();
    expect(itemListExportBusy, isTrue);
  });
}

class _MemoryDesktopPrefsStore extends DesktopPrefsStore {
  _MemoryDesktopPrefsStore() : super(supportDir: null);

  DesktopPrefs _prefs = DesktopPrefs.defaults;

  @override
  Future<DesktopPrefs> load() async => _prefs;

  @override
  Future<void> save(DesktopPrefs prefs) async {
    _prefs = prefs;
  }
}
