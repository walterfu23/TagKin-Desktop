import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart'
    hide ItemListExportFormat;
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_jobs.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_page.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';
import 'package:tagkin_desktop/item_lists/item_list_music.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
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
        ApiClient(baseUrl: 'http://music.test', tokenProvider: () => 'tok'),
      );

  int generateCount = 0;
  final List<int> durations = [];
  final List<String> writtenPaths = [];
  final List<List<String>?> avoidHistory = [];
  final List<int?> loopCounts = [];

  @override
  Future<EstimateMusicResponse> estimate({required int durationMs}) async {
    return const EstimateMusicResponse(creditsUsed: 0);
  }

  @override
  Future<GenerateMusicResponse> generate({
    required int durationMs,
    required String prompt,
    List<String>? avoidSoundtrackIds,
    int? maxLoops,
  }) async {
    generateCount++;
    durations.add(durationMs);
    avoidHistory.add(avoidSoundtrackIds);
    loopCounts.add(maxLoops);
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

  test('itemListLeaveBusyBody names music generate only', () {
    expect(itemListLeaveBusyBody(generatingMusic: false), isNull);
    expect(
      itemListLeaveBusyBody(generatingMusic: true),
      contains('still generating'),
    );
  });

  test('itemListQuitExportsBody names the in-flight count', () {
    expect(itemListQuitExportsBody(0), isEmpty);
    expect(itemListQuitExportsBody(1), contains('1 export'));
    expect(itemListQuitExportsBody(1), contains('cancel it'));
    expect(itemListQuitExportsBody(3), contains('3 exports'));
    expect(itemListQuitExportsBody(3), contains('cancel them'));
  });

  testWidgets('views dropdown, stills, and export use the current row order', (
    tester,
  ) async {
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

    expect(find.text('Export Views'), findsOneWidget);
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
    expect(
      find.byKey(const Key('item-list-drag-photo-photo-a')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('item-hover-preview-photo-a')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('item-list-description')),
      'Beach weekend',
    );
    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-format-json')));
    await tester.pumpAndSettle();
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
    expect(
      find.byKey(const Key('item-list-drag-photo-photo-b')),
      findsOneWidget,
    );
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
    await ProviderScope.containerOf(
      ctx,
    ).read(collectionsControllerProvider).bootstrapSession(const []);
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

  testWidgets('opens on dirty View01 Hide folder using Folders live filters', (
    tester,
  ) async {
    const trip = 'albums/Trip';
    const view01 = SavedView(
      id: 'v-view01',
      name: 'View01',
      filters: LibraryViewFilters(),
    );
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(id: 'c1', name: 'Trip', leafFolders: [], views: [view01]),
        ],
        currentCollectionId: 'c1',
      ),
    );
    final container = ProviderContainer(
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [
            fixtureItem(id: 'hidden-folder', sourceRef: 'albums/Trip/a.jpg'),
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
  });

  testWidgets('Export tiles show stored sharpness when the pref is on', (
    tester,
  ) async {
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

  testWidgets('Export tiles omit sharpness when the pref is off', (
    tester,
  ) async {
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
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
        saveJson: (json) async {
          exported = json;
          return '/tmp/item-list.out';
        },
      ),
    );

    expect(find.byKey(const Key('item-list-format-menu')), findsOneWidget);
    expect(find.text('MP4 (with music)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    final formats = tester
        .widgetList<PopupMenuItem<ItemListExportFormat>>(
          find.byType(PopupMenuItem<ItemListExportFormat>),
        )
        .map((item) => item.value)
        .toList();
    expect(formats, [
      ItemListExportFormat.mp4WithMusic,
      ItemListExportFormat.mp4,
      ItemListExportFormat.fcp7Xml,
      ItemListExportFormat.fcpxml,
      ItemListExportFormat.json,
    ]);

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

  testWidgets('MP4 format shows generate music, not a vendor name', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
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

    expect(
      find.byKey(const Key('item-list-music-prompt-preset')),
      findsOneWidget,
    );
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

  testWidgets('Try another keeps takes and switching chips changes preview', (
    tester,
  ) async {
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
      findsNothing,
    );
    expect(find.byKey(const Key('item-list-music-error')), findsNothing);

    expect(music.generateCount, 1);
    expect(music.durations.single, 7000);
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

    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-format-json')));
    await tester.pumpAndSettle();
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

  testWidgets('MP4 job row shows encode phase, pause, and cancel', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
      ),
    );

    final ctx = tester.element(find.byType(ItemListExportPage));
    final jobs = ProviderScope.containerOf(
      ctx,
    ).read(itemListExportJobManagerProvider);
    final job = jobs.stageJob(
      outputPath: '/tmp/tagkin-d13-widget-job.mp4',
      phase: ItemListMp4Phase.staging,
    );
    await tester.pump();
    expect(find.byKey(const Key('item-list-export-jobs')), findsOneWidget);
    expect(find.text('Preparing files…'), findsOneWidget);
    expect(find.byKey(Key('item-list-job-pause-${job.id}')), findsOneWidget);
    expect(find.byKey(Key('item-list-job-cancel-${job.id}')), findsOneWidget);

    job.setProgress(
      const ItemListMp4Progress(
        phase: ItemListMp4Phase.encodingClips,
        clipIndex: 1,
        clipCount: 2,
      ),
    );
    await tester.pump();
    expect(find.text('Encoding clip 1 of 2…'), findsOneWidget);

    await tester.tap(find.byKey(Key('item-list-job-pause-${job.id}')));
    await tester.pump();
    expect(find.textContaining('Paused'), findsOneWidget);
    expect(find.byKey(Key('item-list-job-continue-${job.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('item-list-job-continue-${job.id}')));
    await tester.pump();
    expect(find.text('Encoding clip 1 of 2…'), findsOneWidget);

    job.setProgress(
      const ItemListMp4Progress(phase: ItemListMp4Phase.assembling),
    );
    await tester.pump();
    expect(find.text('Composing video…'), findsOneWidget);

    job.setProgress(
      const ItemListMp4Progress(phase: ItemListMp4Phase.writingOut),
    );
    await tester.pump();
    expect(find.text('Writing file…'), findsOneWidget);

    await tester.tap(find.byKey(Key('item-list-job-cancel-${job.id}')));
    await tester.pump();
    expect(job.state, ItemListExportJobState.cancelled);
    expect(find.text('Cancelled'), findsOneWidget);
  });

  testWidgets('failed export row shows a plain reason and Details', (
    tester,
  ) async {
    await _pumpPage(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
      ),
    );
    final report = itemListMp4FailureReport(
      step: 'assembling',
      exitCode: -22,
      stderr:
          '[swscaler @ 0x1] No accelerated colorspace conversion '
          'found from yuv420p to bgr24.\n'
          '[aist#0] Guessed Channel Layout: stereo\n'
          'Failed to configure output pad on Parsed_xfade_391',
      logDir: '/tmp/tagkin-mp4-view02',
    );
    final ctx = tester.element(find.byType(ItemListExportPage));
    final jobs = ProviderScope.containerOf(
      ctx,
    ).read(itemListExportJobManagerProvider);
    final job = jobs.stageJob(
      outputPath: '/tmp/view02.mp4',
      state: ItemListExportJobState.failed,
      error: report.sentence,
      failure: report,
    );
    await tester.pump();

    expect(find.text(report.sentence), findsOneWidget);
    expect(find.textContaining('swscaler'), findsNothing);
    expect(find.textContaining('Guessed Channel Layout'), findsNothing);
    expect(find.byKey(Key('item-list-job-details-${job.id}')), findsOneWidget);

    await tester.tap(find.byKey(Key('item-list-job-details-${job.id}')));
    await tester.pump();
    expect(find.textContaining('Exit -22'), findsOneWidget);
    expect(find.textContaining('assembling'), findsOneWidget);
    expect(find.text('/tmp/tagkin-mp4-view02'), findsOneWidget);
    expect(find.textContaining('Parsed_xfade_391'), findsOneWidget);
    expect(find.textContaining('swscaler'), findsNothing);
  });

  testWidgets(
    'short window keeps the filmstrip when exports and preview are tall',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final overflows = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          overflows.add(details);
        }
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      final music = FakeMusicRepository();
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
        ),
      );

      await tester.tap(find.byKey(const Key('item-list-format-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('item-list-format-mp4WithMusic')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const Key('item-list-music-prompt')),
      );
      await tester.enterText(
        find.byKey(const Key('item-list-music-prompt')),
        'quiet piano',
      );
      await tester.pump();
      await tester.ensureVisible(
        find.byKey(const Key('item-list-generate-music')),
      );
      await tester.tap(find.byKey(const Key('item-list-generate-music')));
      await tester.pumpAndSettle();
      expect(find.byType(ItemListSlideshowPreview), findsOneWidget);

      final ctx = tester.element(find.byType(ItemListExportPage));
      final jobs = ProviderScope.containerOf(
        ctx,
      ).read(itemListExportJobManagerProvider);
      for (var i = 0; i < 4; i++) {
        jobs.stageJob(
          outputPath: '/tmp/tagkin-d13-short-$i.mp4',
          state: i == 3
              ? ItemListExportJobState.failed
              : ItemListExportJobState.running,
          phase: ItemListMp4Phase.encodingClips,
          clipIndex: 1,
          clipCount: 12,
          error: i == 3 ? 'Could not write the video. ${'x' * 240}' : null,
        );
      }
      await tester.pump();

      expect(overflows, isEmpty);
      expect(tester.takeException(), isNull);
      final filmstrip = find.byKey(const Key('item-list-filmstrip'));
      expect(filmstrip, findsOneWidget);
      expect(tester.getSize(filmstrip).height, greaterThan(180));
      expect(find.text('Photo').hitTestable(), findsWidgets);
      expect(find.byKey(const Key('item-list-export-jobs')), findsOneWidget);
    },
  );

  testWidgets('switching views while an MP4 encodes keeps Export enabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final hang = Completer<void>();
    Timer? ticks;
    addTearDown(() {
      ticks?.cancel();
      if (!hang.isCompleted) hang.complete();
    });

    var saves = 0;
    final stems = <String>[];
    final music = FakeMusicRepository();
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

    Future<void> render({
      required ItemListNleTimeline timeline,
      required String? audioPath,
      required String outputPath,
      required int sequenceWidth,
      required int sequenceHeight,
      required bool scaleToFit,
      double soundtrackDuck = 0,
      ItemListMp4ProgressCallback? onProgress,
      ItemListMp4CancelToken? cancel,
      String? macSaveHandle,
    }) async {
      void report() {
        onProgress?.call(
          const ItemListMp4Progress(
            phase: ItemListMp4Phase.encodingClips,
            clipIndex: 1,
            clipCount: 2,
          ),
        );
      }

      report();
      ticks?.cancel();
      ticks = Timer.periodic(const Duration(milliseconds: 30), (_) {
        if (hang.isCompleted || (cancel?.isCancelled ?? false)) return;
        report();
      });
      await hang.future;
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ..._overrides(
            items: FakeItemsRepository(
              items: [
                fixtureItem(id: 'keep', sourceRef: 'keep'),
                fixtureItem(id: 'keep-b', sourceRef: 'keep-b'),
                fixtureItem(id: 'drop', sourceRef: 'other'),
              ],
            ),
            collections: store,
            music: music,
          ),
          itemListMp4RendererProvider.overrideWithValue(render),
          itemListSavePathPickerProvider.overrideWithValue(({
            required String fileExtension,
            required String fileStem,
          }) async {
            stems.add(fileStem);
            saves += 1;
            return ItemListSavePick(path: '/tmp/tagkin-export-$saves.mp4');
          }),
        ],
        child: const MaterialApp(
          home: SelectableScope(child: ItemListExportPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final ctx = tester.element(find.byType(ItemListExportPage));
    await ProviderScope.containerOf(
      ctx,
    ).read(collectionsControllerProvider).bootstrapSession(const []);
    await tester.pumpAndSettle();

    expect(find.text('3 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('item-list-format-mp4WithMusic')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('item-list-music-prompt')),
      'quiet piano',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('item-list-generate-music')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('item-list-export')));
    await _pumpUntil(tester, find.text('Encoding clip 1 of 2…'));
    await tester.pump(const Duration(milliseconds: 90));

    expect(find.text('3 items'), findsOneWidget);
    expect(find.byKey(const Key('item-list-drag-photo-keep')), findsOneWidget);
    expect(
      find.byKey(const Key('item-list-drag-photo-keep-b')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('item-list-drag-photo-drop')), findsOneWidget);
    expect(_exportEnabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('item-list-views-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('item-list-views-v-keep')));
    await _pumpUntil(tester, find.text('2 items'));

    expect(find.byKey(const Key('item-list-drag-photo-keep')), findsOneWidget);
    expect(
      find.byKey(const Key('item-list-drag-photo-keep-b')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('item-list-drag-photo-drop')), findsNothing);
    expect(find.text('Encoding clip 1 of 2…'), findsOneWidget);
    expect(_exportEnabled(tester), isTrue);
    expect(stems, ['All']);
    expect(find.byType(ItemListSlideshowPreview), findsNothing);
    expect(find.text('Generate music'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-generate-music')));
    await _pumpUntil(tester, find.byType(ItemListSlideshowPreview));

    await tester.tap(find.byKey(const Key('item-list-export')));
    await _pumpUntil(tester, find.text('tagkin-export-2.mp4'));

    expect(stems, ['All', 'Keep']);

    expect(find.text('tagkin-export-1.mp4'), findsOneWidget);
    expect(find.text('tagkin-export-2.mp4'), findsOneWidget);
    expect(
      find.byKey(const Key('item-list-export-job-export-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('item-list-export-job-export-2')),
      findsOneWidget,
    );
    expect(find.text('2 items'), findsOneWidget);

    ticks?.cancel();
    if (!hang.isCompleted) hang.complete();
    await tester.pump();
  });

  testWidgets('Back leaves Export list while an MP4 job keeps running', (
    tester,
  ) async {
    await _pumpExportOnStack(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
      ),
    );
    final ctx = tester.element(find.byType(ItemListExportPage));
    final jobs = ProviderScope.containerOf(
      ctx,
    ).read(itemListExportJobManagerProvider);
    final job = jobs.stageJob(
      outputPath: '/tmp/tagkin-d13-widget-job.mp4',
      phase: ItemListMp4Phase.encodingClips,
      clipIndex: 1,
      clipCount: 2,
    );
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('item-list-leave-encoding-dialog')),
      findsNothing,
    );
    expect(find.byType(ItemListExportPage), findsNothing);
    expect(job.state, ItemListExportJobState.running);
  });

  testWidgets('Folders leaves Export list without cancelling an MP4 job', (
    tester,
  ) async {
    await _pumpExportOnStack(
      tester,
      overrides: _overrides(
        items: FakeItemsRepository(
          items: [fixtureItem(id: 'photo-a', sourceRef: '')],
        ),
      ),
    );
    final ctx = tester.element(find.byType(ItemListExportPage));
    final jobs = ProviderScope.containerOf(
      ctx,
    ).read(itemListExportJobManagerProvider);
    final job = jobs.stageJob(
      outputPath: '/tmp/tagkin-d13-widget-job.mp4',
      phase: ItemListMp4Phase.assembling,
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('nav-folders')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('item-list-leave-encoding-dialog')),
      findsNothing,
    );
    expect(find.byType(ItemListExportPage), findsNothing);
    expect(find.byKey(const Key('open-export')), findsOneWidget);
    expect(job.state, ItemListExportJobState.running);
  });

  testWidgets('leave dialog uses music copy when generating', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () {
              unawaited(
                confirmLeaveItemListBusy(context: ctx, generatingMusic: true),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('item-list-leave-encoding-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('still generating'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-leave-stay')));
    await tester.pumpAndSettle();
  });

  testWidgets('an MP4 job does not mark the page leave-busy flag', (
    tester,
  ) async {
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
    final jobs = ProviderScope.containerOf(
      ctx,
    ).read(itemListExportJobManagerProvider);
    jobs.stageJob(
      outputPath: '/tmp/tagkin-d13-widget-job.mp4',
      phase: ItemListMp4Phase.encodingClips,
      clipIndex: 1,
      clipCount: 2,
    );
    await tester.pump();
    expect(itemListExportBusy, isFalse);
    expect(jobs.hasActive, isTrue);
  });

  testWidgets('quit dialog offers Stay and Quit for in-flight exports', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => TextButton(
            onPressed: () {
              unawaited(
                confirmQuitItemListExports(context: ctx, activeCount: 2),
              );
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('item-list-quit-exports-dialog')),
      findsOneWidget,
    );
    expect(find.textContaining('2 exports'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-quit-exports-stay')));
    await tester.pumpAndSettle();
  });

  testWidgets('MP4 without music hides generate and exports without audio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    String? renderedAudio = 'unset';
    await _pumpPage(
      tester,
      overrides: [
        ..._overrides(
          items: FakeItemsRepository(
            items: [fixtureItem(id: 'photo-a', sourceRef: '')],
          ),
        ),
        itemListMp4RendererProvider.overrideWithValue(({
          required timeline,
          required audioPath,
          required outputPath,
          required sequenceWidth,
          required sequenceHeight,
          required scaleToFit,
          soundtrackDuck = 0.05,
          onProgress,
          cancel,
          macSaveHandle,
        }) async {
          renderedAudio = audioPath;
          await File(outputPath).writeAsBytes(const [1, 2, 3, 4]);
        }),
        itemListSavePathPickerProvider.overrideWithValue(({
          required String fileExtension,
          required String fileStem,
        }) async {
          return const ItemListSavePick(path: '/tmp/tagkin-no-music.mp4');
        }),
      ],
    );

    expect(find.text('1 item'), findsOneWidget);
    expect(find.byKey(const Key('item-list-generate-music')), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-format-menu')));
    await tester.pumpAndSettle();
    expect(find.text('MP4 (without music)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('item-list-format-mp4')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item-list-generate-music')), findsNothing);
    expect(find.byKey(const Key('item-list-music-prompt')), findsNothing);
    expect(find.text('MP4 (without music)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-list-export')));
    await _pumpUntil(tester, find.text('tagkin-no-music.mp4'));
    expect(find.text('Generate music before exporting MP4'), findsNothing);
    expect(renderedAudio, isNull);
  });

  test('Export Views is the title, toolbar tooltip, and File menu', () {
    final page = File(
      'lib/item_lists/item_list_export_page.dart',
    ).readAsStringSync();
    final shell = File('lib/app_shell.dart').readAsStringSync();
    final menu = File('lib/shell/tagkin_platform_menu.dart').readAsStringSync();
    expect(page.contains("title: const Text('Export Views')"), isTrue);
    expect(shell.contains("tooltip: 'Export Views'"), isTrue);
    expect(shell.contains("const Text('Export Views…')"), isTrue);
    expect(menu.contains("label: 'Export Views…'"), isTrue);
    expect(shell.contains("tooltip: 'Export list'"), isFalse);
    expect(menu.contains("label: 'Export list…'"), isFalse);
  });
}

bool _exportEnabled(WidgetTester tester) {
  final button = tester.widget<ButtonStyleButton>(
    find.byKey(const Key('item-list-export')),
  );
  return button.onPressed != null;
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 40; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail('Timed out waiting for $finder');
}

class _MemoryDesktopPrefsStore extends DesktopPrefsStore {
  _MemoryDesktopPrefsStore({DesktopPrefs? initial})
    : _prefs = initial ?? DesktopPrefs.defaults,
      super(supportDir: null);

  DesktopPrefs _prefs;

  @override
  Future<DesktopPrefs> load() async => _prefs;

  @override
  Future<void> save(DesktopPrefs prefs) async {
    _prefs = prefs;
  }
}
