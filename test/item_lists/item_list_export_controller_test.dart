import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';
import 'package:tagkin_desktop/item_lists/item_list_media_size.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/library/library_table_controller.dart';
import 'package:tagkin_desktop/library/local_thumb_cache.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

import '../fake_comments_repository.dart';
import '../fake_items_repository.dart';

class _RecordingThumbCache extends LocalThumbCache {
  int? lastKeyPeriodTimestampMs;
  String? lastKeyPeriodId;

  @override
  Future<LocalThumbResult> resolveKeyPeriod(
    Item item, {
    required String keyPeriodId,
    required int timestampMs,
  }) async {
    lastKeyPeriodId = keyPeriodId;
    lastKeyPeriodTimestampMs = timestampMs;
    return const LocalThumbResult(status: LocalMediaStatus.missing);
  }
}

ItemListExportController _controller({
  FakeItemsRepository? items,
  LocalThumbCache? thumbCache,
  ItemListJsonSaver? saveJson,
  ItemListSavePathPicker? pickSavePath,
  ItemListMp4Renderer? renderMp4,
  ItemListMediaSizeProbe? probeMediaSize,
}) {
  return ItemListExportController(
    itemsRepository: items ?? FakeItemsRepository(),
    commentsRepository: FakeCommentsRepository(),
    thumbCache: thumbCache,
    saveJson: saveJson,
    pickSavePath: pickSavePath,
    renderMp4: renderMp4,
    probeMediaSize: probeMediaSize,
  );
}

Future<void> _waitUntil(
  bool Function() done, {
  int ticks = 80,
}) async {
  for (var i = 0; i < ticks; i++) {
    if (done()) return;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('load flattens photos into filmstrip entries', () async {
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg'),
          fixtureItem(id: 'b', sourceRef: 'file:///albums/b.jpg'),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.length >= 2);
    expect(controller.entries.map((e) => e.itemId), ['a', 'b']);
    expect(
      controller.entries.every((e) => e.kind == ItemListEntryKind.photo),
      isTrue,
    );
  });

  test('export of MP4 format throws (use exportMp4)', () async {
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg'),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.hasEntries, isTrue);
    await expectLater(
      controller.export(format: ItemListExportFormat.mp4WithMusic),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('load expands each video key period', () async {
    final item = fixtureItem(id: 'video-1', type: ItemType.video);
    final controller = _controller(
      items: FakeItemsRepository(
        items: [item],
        knowledgeByItemId: {
          'video-1': fixtureKnowledge(
            item: item,
            keyPeriods: [
              const KeyPeriodKnowledge(
                id: 'kp-1',
                itemId: 'video-1',
                startMs: 0,
                endMs: 1000,
                sampleTimestampMs: 800,
                tags: [],
              ),
              const KeyPeriodKnowledge(
                id: 'kp-2',
                itemId: 'video-1',
                startMs: 2000,
                endMs: 4000,
                sampleTimestampMs: 2500,
                tags: [],
              ),
            ],
          ),
        },
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(
      () => controller.entries.length == 2 &&
          !controller.libraryTable.knowledgeWarming,
    );
    expect(controller.entries.map((e) => e.keyPeriodId), ['kp-1', 'kp-2']);
    expect(controller.entries.map((e) => e.startMs), [0, 2000]);
    expect(
      controller.entries.every((e) => e.kind == ItemListEntryKind.keyperiod),
      isTrue,
    );
  });

  test('reorder updates export JSON order', () async {
    String? saved;
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg'),
          fixtureItem(id: 'b', sourceRef: 'file:///albums/b.jpg'),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.json';
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.length >= 2);
    expect(controller.entries.map((e) => e.itemId), ['a', 'b']);
    controller.reorder(0, 1);
    expect(controller.entries.map((e) => e.itemId), ['b', 'a']);
    final path = await controller.exportJson(
      description: 'Trip',
      exportedAt: DateTime.utc(2026, 9, 11, 12),
    );
    expect(path, '/tmp/item-list.json');
    final doc = jsonDecode(saved!) as Map<String, dynamic>;
    expect(doc['description'], 'Trip');
    expect(doc['exportedAt'], '2026-09-11T12:00:00.000Z');
    expect(doc['view'], isNull);
    final entries = doc['entries'] as List<dynamic>;
    expect((entries[0] as Map)['itemId'], 'b');
    expect((entries[0] as Map)['path'], '/albums/b.jpg');
    expect((entries[1] as Map)['itemId'], 'a');
  });

  test('removeAt drops the row from JSON export', () async {
    String? saved;
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a'),
          fixtureItem(id: 'b'),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.json';
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.length >= 2);
    controller.removeAt(0);
    expect(controller.entries.map((e) => e.itemId), ['b']);
    await controller.exportJson();
    final ids = (jsonDecode(saved!)['entries'] as List<dynamic>)
        .map((e) => (e as Map)['itemId'])
        .toList();
    expect(ids, ['b']);
  });

  test('selectView applies Folders view filters', () async {
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'keep', sourceRef: 'file:///albums/keep.jpg'),
          fixtureItem(id: 'drop', sourceRef: 'file:///albums/other.jpg'),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.length >= 2);
    await controller.selectView(
      const SavedView(
        id: 'v1',
        name: 'Keep',
        filters: LibraryViewFilters(filterQuery: 'keep'),
      ),
    );
    await _waitUntil(() => controller.entries.length == 1);
    expect(controller.entries.map((e) => e.itemId), ['keep']);
    expect(controller.selectedView?.id, 'v1');
  });

  test('exportViewMatchingFolders overlays live Hide folder on current view',
      () {
    final folders = LibraryTableController(
      itemsRepository: FakeItemsRepository(),
      commentsRepository: FakeCommentsRepository(),
      thumbCache: LocalThumbCache(),
    );
    addTearDown(folders.dispose);
    folders.setActiveView('v-view01', const LibraryViewFilters());
    folders.setFolderHidden('/albums/Trip', hidden: true);
    const stored = SavedView(
      id: 'v-view01',
      name: 'View01',
      filters: LibraryViewFilters(),
    );
    expect(
      exportViewMatchingFolders(stored, folders).filters.hiddenFolders,
      ['/albums/Trip'],
    );
    const other = SavedView(
      id: 'v-other',
      name: 'Other',
      filters: LibraryViewFilters(),
    );
    expect(
      exportViewMatchingFolders(other, folders).filters.hiddenFolders,
      isEmpty,
    );
  });

  test('load(view:) applies the Folders view before publishing entries', () async {
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'keep', sourceRef: 'file:///albums/keep.jpg'),
          fixtureItem(id: 'drop', sourceRef: 'file:///albums/other.jpg'),
        ],
      ),
    );
    addTearDown(controller.dispose);
    await controller.load(
      view: const SavedView(
        id: 'v1',
        name: 'Keep',
        filters: LibraryViewFilters(filterQuery: 'keep'),
      ),
    );
    await _waitUntil(() => controller.selectedView?.id == 'v1');
    expect(controller.entries.map((e) => e.itemId), ['keep']);
  });

  test('thumbFor uses key-period startMs, not sampleTimestampMs', () async {
    final cache = _RecordingThumbCache();
    final item = fixtureItem(id: 'video-1', type: ItemType.video);
    final controller = _controller(
      items: FakeItemsRepository(
        items: [item],
        knowledgeByItemId: {
          'video-1': fixtureKnowledge(
            item: item,
            keyPeriods: [
              const KeyPeriodKnowledge(
                id: 'kp-1',
                itemId: 'video-1',
                startMs: 1500,
                endMs: 4000,
                sampleTimestampMs: 800,
                tags: [],
              ),
            ],
          ),
        },
      ),
      thumbCache: cache,
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.length == 1);
    await controller.thumbFor(controller.entries.single);
    expect(cache.lastKeyPeriodId, 'kp-1');
    expect(cache.lastKeyPeriodTimestampMs, 1500);
  });

  test('export JSON records the selected view', () async {
    String? saved;
    final controller = _controller(
      items: FakeItemsRepository(
        items: [fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg')],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.json';
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.isNotEmpty);
    const view = SavedView(
      id: 'v1',
      name: 'Ada',
      filters: LibraryViewFilters(),
    );
    await controller.selectView(view);
    await controller.exportJson(exportedAt: DateTime.utc(2026, 1, 1));
    final doc = jsonDecode(saved!) as Map<String, dynamic>;
    final recorded = doc['view'] as Map<String, dynamic>;
    expect(recorded['id'], 'v1');
    expect(recorded['name'], 'Ada');
    expect((recorded['filters'] as Map)['whoNames'], <dynamic>[]);
  });

  test('export FCP7 XML and FCPXML use the filmstrip order', () async {
    String? saved;
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg'),
          fixtureItem(id: 'b', sourceRef: 'file:///albums/b.jpg'),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.xml';
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.length >= 2);
    controller.reorder(0, 1);
    var path = await controller.export(
      format: ItemListExportFormat.fcp7Xml,
      description: 'Trip',
    );
    expect(path, '/tmp/item-list.xml');
    expect(saved, contains('<xmeml version="4">'));
    expect(saved, contains('<name>Trip</name>'));
    final xml = saved!;
    expect(xml.indexOf('b.jpg'), lessThan(xml.indexOf('a.jpg')));

    path = await controller.export(
      format: ItemListExportFormat.fcpxml,
      description: 'Trip',
    );
    expect(saved, contains('<fcpxml version="1.9">'));
    expect(saved, contains('<project name="Trip">'));
    expect(ItemListExportFormat.fcpxml.fileExtension, 'fcpxml');
  });

  test('export FCP7 XML match smallest uses min probed size and scales',
      () async {
    String? saved;
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a', sourceRef: 'file:///albums/wide.jpg'),
          fixtureItem(id: 'b', sourceRef: 'file:///albums/hd.jpg'),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.xml';
      },
      probeMediaSize: (path, {required isStill}) async {
        if (path.contains('wide')) {
          return const ItemListPixelSize(4032, 1816);
        }
        return const ItemListPixelSize(1920, 1080);
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.length >= 2);
    await controller.export(
      format: ItemListExportFormat.fcp7Xml,
      sequenceSize: ExportSequenceSize.matchSmallest,
    );
    expect(saved, contains('<width>1920</width>'));
    expect(saved, contains('<height>1080</height>'));
    expect(saved, contains('<width>4032</width>'));
    expect(saved, contains('<effectid>basic</effectid>'));
    expect(saved, contains('<value>47.619</value>'));
  });

  test('export FCP7 XML match largest uses probed still size', () async {
    String? saved;
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a', sourceRef: 'file:///albums/wide.jpg'),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.xml';
      },
      probeMediaSize: (path, {required isStill}) async {
        expect(isStill, isTrue);
        return const ItemListPixelSize(4032, 1816);
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.isNotEmpty);
    await controller.export(
      format: ItemListExportFormat.fcp7Xml,
      sequenceSize: ExportSequenceSize.matchLargest,
    );
    expect(saved, contains('<width>4032</width>'));
    expect(saved, contains('<height>1816</height>'));
    expect(saved, isNot(contains('<effectid>basic</effectid>')));
  });

  test('export FCP7 XML 1080p scales probed still', () async {
    String? saved;
    final controller = _controller(
      items: FakeItemsRepository(
        items: [
          fixtureItem(id: 'a', sourceRef: 'file:///albums/wide.jpg'),
        ],
      ),
      saveJson: (json) async {
        saved = json;
        return '/tmp/item-list.xml';
      },
      probeMediaSize: (path, {required isStill}) async =>
          const ItemListPixelSize(4032, 1816),
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.entries.isNotEmpty);
    await controller.export(
      format: ItemListExportFormat.fcp7Xml,
      sequenceSize: ExportSequenceSize.p1080,
    );
    expect(saved, contains('<width>1920</width>'));
    expect(saved, contains('<width>4032</width>'));
    expect(saved, contains('<value>47.619</value>'));
  });

  test('exportMp4 cancel skips render', () async {
    final events = <String>[];
    final controller = _controller(
      items: FakeItemsRepository(
        items: [fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg')],
      ),
      pickSavePath: ({required fileExtension}) async {
        events.add('pick:$fileExtension');
        return null;
      },
      renderMp4: ({
        required timeline,
        required audioPath,
        required outputPath,
        required sequenceWidth,
        required sequenceHeight,
        required scaleToFit,
        soundtrackDuck = 0.05,
      }) async {
        events.add('render');
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.hasEntries);
    expect(await controller.exportMp4(audioPath: '/tmp/a.wav'), isNull);
    expect(events, ['pick:mp4']);
  });

  test('exportMp4 picks save path before render', () async {
    final events = <String>[];
    String? renderedTo;
    final controller = _controller(
      items: FakeItemsRepository(
        items: [fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg')],
      ),
      pickSavePath: ({required fileExtension}) async {
        events.add('pick:$fileExtension');
        return '/tmp/out.mp4';
      },
      renderMp4: ({
        required timeline,
        required audioPath,
        required outputPath,
        required sequenceWidth,
        required sequenceHeight,
        required scaleToFit,
        soundtrackDuck = 0.05,
      }) async {
        events.add('render');
        renderedTo = outputPath;
        await File(outputPath).writeAsBytes(const [0, 1, 2, 3, 4, 5, 6, 7]);
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.hasEntries);
    expect(
      await controller.exportMp4(audioPath: '/tmp/a.wav'),
      '/tmp/out.mp4',
    );
    expect(events, ['pick:mp4', 'render']);
    expect(renderedTo, '/tmp/out.mp4');
    addTearDown(() {
      final f = File('/tmp/out.mp4');
      if (f.existsSync()) f.deleteSync();
    });
  });

  test('exportMp4 fails closed on an empty dest and deletes leftover', () async {
    final dest = File(
      '${Directory.systemTemp.path}/tagkin-empty-export.mp4',
    );
    if (dest.existsSync()) dest.deleteSync();
    dest.createSync();
    addTearDown(() {
      if (dest.existsSync()) dest.deleteSync();
    });
    final controller = _controller(
      items: FakeItemsRepository(
        items: [fixtureItem(id: 'a', sourceRef: 'file:///albums/a.jpg')],
      ),
      pickSavePath: ({required fileExtension}) async => dest.path,
      renderMp4: ({
        required timeline,
        required audioPath,
        required outputPath,
        required sequenceWidth,
        required sequenceHeight,
        required scaleToFit,
        soundtrackDuck = 0.05,
      }) async {},
    );
    addTearDown(controller.dispose);
    await controller.load();
    await _waitUntil(() => controller.hasEntries);
    await expectLater(
      controller.exportMp4(audioPath: '/tmp/a.wav'),
      throwsA(isA<ItemListMp4RenderException>()),
    );
    expect(dest.existsSync(), isFalse);
  });
}
