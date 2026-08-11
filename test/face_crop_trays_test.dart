import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/folder_ingest_queue.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/face_crop_trays_page.dart';

import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';

Uint8List _solidJpeg() {
  final image = img.Image(width: 120, height: 120);
  img.fill(image, color: img.ColorRgb8(180, 90, 40));
  return Uint8List.fromList(img.encodeJpg(image));
}

FakeItemsRepository _itemsInAlbum(
  List<String> itemIds, {
  String album = 'Trip',
  FakePersonsRepository? linkedPersons,
}) {
  return FakeItemsRepository(
    items: [
      for (final id in itemIds)
        fixtureItem(
          id: id,
          sourceRef: 'file:///albums/$album/$id.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
    ],
    linkedPersons: linkedPersons,
  );
}

String _exclusionIdForTag(FakePersonsRepository persons, String tagId) {
  for (final e in persons.accountExclusions) {
    if (e.createdFromTagId == tagId) return e.id;
  }
  fail('No exclusion for tag $tagId');
}

String _unassignedIdForTag(FakePersonsRepository persons, String tagId) {
  for (final a in persons.unassignedAppearances) {
    if (a.tagId == tagId) return a.id;
  }
  fail('No unassigned appearance for tag $tagId');
}

void main() {
  setUp(() {
    faceCropLastLeafFolder = null;
    debugFaceCropMetaPressed = null;
    debugFaceCropShiftPressed = null;
  });

  tearDown(() {
    debugFaceCropMetaPressed = null;
    debugFaceCropShiftPressed = null;
  });

  testWidgets('face crop trays: loads unassigned + excluded columns',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_assigned',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_u',
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.2,
          xMin: 0.2,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
    );
    persons.accountExclusions.add(
      const WhoExclusion(
        id: 'ex_1',
        itemId: 'item_e',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_e',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_u', 'item_e']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-folder-select')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-tray-assigned')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-tray-unassigned')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-tray-excluded')), findsOneWidget);
    expect(find.text('named people'), findsOneWidget);
    expect(
      find.text('not yet named — includes auto-grouped similar faces'),
      findsOneWidget,
    );
    expect(find.text('faces should not be assigned to a person'), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_u')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-set-name-ap_u')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-exclusion-ex_1')), findsOneWidget);
    expect(
      find.byKey(const Key('face-crop-appearance-ap_assigned')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('face-crop-set-name-ap_assigned')),
      findsNothing,
    );
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-name')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-unassign')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: unassigned + excluded tiles show Image crops',
      (tester) async {
    late final Directory dir;
    late final Item itemU;
    late final Item itemE;
    late final Item itemA;

    // Widget-test zone does not complete real dart:io without runAsync.
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('face_crop_trays_');
      Future<Item> seedPhoto(String id) async {
        final file = File('${dir.path}/$id.jpg');
        await file.writeAsBytes(_solidJpeg());
        return fixtureItem(
          id: id,
          type: ItemType.photo,
          sourceRef: Uri.file(file.path).toString(),
          contentHash: null,
          processingStatus: ProcessingStatus.tagged,
        );
      }

      itemU = await seedPhoto('item_u');
      itemE = await seedPhoto('item_e');
      itemA = await seedPhoto('item_a');
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
    });

    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_assigned',
              personId: 'person_1',
              itemId: itemA.id,
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.5,
                xMax: 0.5,
              ),
            ),
          ],
        ),
      ],
    );
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: itemU.id,
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
    );
    persons.accountExclusions.add(
      WhoExclusion(
        id: 'ex_1',
        itemId: itemE.id,
        region: const TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.5, xMax: 0.5),
        createdFromTagId: 'tag_e',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            personsRepositoryProvider.overrideWithValue(persons),
            itemsRepositoryProvider.overrideWithValue(
              FakeItemsRepository(items: [itemU, itemE, itemA]),
            ),
          ],
          child: const MaterialApp(
            home: FaceCropTraysPage(initialPersonId: 'person_1'),
          ),
        ),
      );
      await tester.pump(); // post-frame _reload
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(); // trays + thumb FutureBuilders start
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump(); // Image.memory after crop
    });

    expect(find.byKey(const Key('face-crop-appearance-ap_u')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-exclusion-ex_1')), findsOneWidget);
    expect(find.byKey(const Key('who-exclusion-thumb-item_u')), findsWidgets);
    expect(find.byKey(const Key('who-exclusion-thumb-item_e')), findsWidgets);

    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-appearance-ap_u')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-exclusion-ex_1')),
        matching: find.byType(Image),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'face crop trays: clears person dropdown when selection leaves the list',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_assigned',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);

    // Simulate exclude pruning the person (API removes them from listPersons).
    await persons.deletePerson('person_1');
    await tester.tap(find.byKey(const Key('face-crop-trays-refresh')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('face-crop-assigned-empty')), findsOneWidget);
    // Deleted person's faces land in Unassigned → New Person... stays available.
    expect(find.byKey(const Key('face-crop-person-select')), findsOneWidget);
    expect(find.text('Drop faces to name a new person'), findsWidgets);
  });

  testWidgets(
      'face crop trays: renaming selected person keeps chrome in view mode',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_named',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_named',
              personId: 'person_named',
              itemId: 'item_a',
              tagId: 'tag_a',
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_other',
          name: 'Bea',
          appearances: [
            fixtureAppearance(
              id: 'ap_other',
              personId: 'person_other',
              itemId: 'item_b',
              tagId: 'tag_b',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_b']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_named'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-person-rename-start')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('face-crop-person-rename')),
      'Sam Updated',
    );
    await tester.tap(find.byKey(const Key('face-crop-person-rename-done')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-person-name')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Sam Updated',
    );
    expect(
      find.byKey(const Key('face-crop-person-rename-start')),
      findsOneWidget,
    );
  });

  testWidgets(
      'face crop trays: Set name from unassigned loose crop',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_u',
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.2,
          xMin: 0.2,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_u']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-set-name-ap_u')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-name-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('person-name-field')),
      'Riley',
    );
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(persons.reassignCalls, hasLength(1));
    expect(persons.reassignCalls.single.appearanceId, 'ap_u');
    expect(persons.reassignCalls.single.personId, isNull);
    expect(persons.reassignCalls.single.name, 'Riley');
    expect(persons.unassignedAppearances, isEmpty);
    expect(find.byKey(const Key('face-crop-appearance-ap_u')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-name')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Riley',
    );
  });

  testWidgets(
      'face crop trays: click selects; Cmd+click multi-selects',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_u1',
        personId: null,
        itemId: 'item_u1',
        tagId: 'tag_u1',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_u2',
        personId: null,
        itemId: 'item_u2',
        tagId: 'tag_u2',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_u1', 'item_u2']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tap bottom-left — Set name covers the top-right / near-center.
    final u1 = tester.getRect(find.byKey(const Key('face-crop-appearance-ap_u1')));
    await tester.tapAt(Offset(u1.left + 10, u1.bottom - 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-selected-ap_u1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_u2')), findsNothing);

    debugFaceCropMetaPressed = () => true;
    final u2 = tester.getRect(find.byKey(const Key('face-crop-appearance-ap_u2')));
    await tester.tapAt(Offset(u2.left + 10, u2.bottom - 10));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    expect(find.byKey(const Key('face-crop-selected-ap_u1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_u2')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Shift+click selects an inclusive range',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_r1',
        personId: null,
        itemId: 'item_r1',
        tagId: 'tag_r1',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_r2',
        personId: null,
        itemId: 'item_r2',
        tagId: 'tag_r2',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_r3',
        personId: null,
        itemId: 'item_r3',
        tagId: 'tag_r3',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_r1', 'item_r2', 'item_r3']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final r1 = tester.getRect(find.byKey(const Key('face-crop-appearance-ap_r1')));
    await tester.tapAt(Offset(r1.left + 10, r1.bottom - 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-selected-ap_r1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_r3')), findsNothing);

    debugFaceCropShiftPressed = () => true;
    final r3 = tester.getRect(find.byKey(const Key('face-crop-appearance-ap_r3')));
    await tester.tapAt(Offset(r3.left + 10, r3.bottom - 10));
    await tester.pumpAndSettle();
    debugFaceCropShiftPressed = null;

    expect(find.byKey(const Key('face-crop-selected-ap_r1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_r2')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_r3')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Cmd+A selects all loose faces in the active tray',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_c1',
        personId: null,
        itemId: 'item_c1',
        tagId: 'tag_c1',
        faceGroupId: 'fg_fa_cmd',
        faceGroupKind: FaceGroupKind.fa,
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_c2',
        personId: null,
        itemId: 'item_c2',
        tagId: 'tag_c2',
        faceGroupId: 'fg_fa_cmd',
        faceGroupKind: FaceGroupKind.fa,
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_a1',
        personId: null,
        itemId: 'item_a1',
        tagId: 'tag_a1',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_a2',
        personId: null,
        itemId: 'item_a2',
        tagId: 'tag_a2',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_c1', 'item_c2', 'item_a1', 'item_a2']),
          ),
          activeTopLevelTabProvider.overrideWith((ref) => TopLevelTab.faces),
        ],
        // Mirror app shell: SelectionArea above Faces (must not steal Cmd+A).
        child: const MaterialApp(
          home: SelectionArea(
            child: FaceCropTraysPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final a1 = tester.getRect(find.byKey(const Key('face-crop-appearance-ap_a1')));
    await tester.tapAt(Offset(a1.left + 10, a1.bottom - 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-selected-ap_a1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_a2')), findsNothing);

    // Blur Faces Focus; production uses AppShell HardwareKeyboard → registrar.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(facesSelectAllLooseHandler, isNotNull);
    facesSelectAllLooseHandler!();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-selected-ap_a1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_a2')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_c1')), findsNothing);
    expect(find.byKey(const Key('face-crop-selected-ap_c2')), findsNothing);
  });

  testWidgets(
      'face crop trays: Cmd+A selects loose faces with no prior selection',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_n1',
        personId: null,
        itemId: 'item_n1',
        tagId: 'tag_n1',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_n2',
        personId: null,
        itemId: 'item_n2',
        tagId: 'tag_n2',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_n1', 'item_n2']),
          ),
          activeTopLevelTabProvider.overrideWith((ref) => TopLevelTab.faces),
        ],
        child: const MaterialApp(
          home: SelectionArea(
            child: FaceCropTraysPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-selected-ap_n1')), findsNothing);

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    expect(facesSelectAllLooseHandler, isNotNull);
    facesSelectAllLooseHandler!();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-selected-ap_n1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_n2')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Group assembles loose faces into GroupFM; Ungroup dissolves',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_g1',
        personId: null,
        itemId: 'item_g1',
        tagId: 'tag_g1',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_g2',
        personId: null,
        itemId: 'item_g2',
        tagId: 'tag_g2',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_g1', 'item_g2']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final g1 = tester.getRect(find.byKey(const Key('face-crop-appearance-ap_g1')));
    await tester.tapAt(Offset(g1.left + 10, g1.bottom - 10));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    final g2 = tester.getRect(find.byKey(const Key('face-crop-appearance-ap_g2')));
    await tester.tapAt(Offset(g2.left + 10, g2.bottom - 10));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    expect(find.byKey(const Key('face-crop-set-name-ap_g1')), findsNothing);
    expect(find.byKey(const Key('face-crop-set-name-ap_g2')), findsNothing);
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    await tester.tap(find.byKey(const Key('face-crop-group-selection')));
    await tester.pumpAndSettle();

    expect(persons.assembleAppearancesCalls, hasLength(1));
    expect(
      persons.assembleAppearancesCalls.single.toSet(),
      {'ap_g1', 'ap_g2'},
    );
    expect(
      find.byKey(const Key('face-crop-facegroup-fg_fm_1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-ungroup-fg_fm_1')), findsOneWidget);
    expect(find.text('Ungroup'), findsOneWidget);

    await tester.tap(find.byKey(const Key('face-crop-ungroup-fg_fm_1')));
    await tester.pumpAndSettle();
    expect(persons.ungroupFaceGroupCalls, ['fg_fm_1']);
    expect(find.byKey(const Key('face-crop-facegroup-fg_fm_1')), findsNothing);
    expect(find.byKey(const Key('face-crop-appearance-ap_g1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_g2')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Excluded Cmd+click multi-selects loose faces',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(persons: const []);
    persons.accountExclusions.addAll([
      const WhoExclusion(
        id: 'ex_m1',
        itemId: 'item_m1',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
      const WhoExclusion(
        id: 'ex_m2',
        itemId: 'item_m2',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_m1', 'item_m2']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final e1 = tester.getRect(find.byKey(const Key('face-crop-exclusion-ex_m1')));
    await tester.tapAt(Offset(e1.left + 10, e1.bottom - 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-selected-ex_m1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ex_m2')), findsNothing);

    debugFaceCropMetaPressed = () => true;
    final e2 = tester.getRect(find.byKey(const Key('face-crop-exclusion-ex_m2')));
    await tester.tapAt(Offset(e2.left + 10, e2.bottom - 10));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    expect(find.byKey(const Key('face-crop-selected-ex_m1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ex_m2')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Excluded Group assembles loose faces into GroupFM; Ungroup dissolves',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(persons: const []);
    persons.accountExclusions.addAll([
      const WhoExclusion(
        id: 'ex_g1',
        itemId: 'item_eg1',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
      const WhoExclusion(
        id: 'ex_g2',
        itemId: 'item_eg2',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_eg1', 'item_eg2']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final g1 = tester.getRect(find.byKey(const Key('face-crop-exclusion-ex_g1')));
    await tester.tapAt(Offset(g1.left + 10, g1.bottom - 10));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    final g2 = tester.getRect(find.byKey(const Key('face-crop-exclusion-ex_g2')));
    await tester.tapAt(Offset(g2.left + 10, g2.bottom - 10));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
    expect(find.text('Group'), findsOneWidget);
    await tester.tap(find.byKey(const Key('face-crop-group-selection')));
    await tester.pumpAndSettle();

    expect(persons.assembleExclusionsCalls, hasLength(1));
    expect(
      persons.assembleExclusionsCalls.single.toSet(),
      {'ex_g1', 'ex_g2'},
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-excluded')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_fm_1')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-ungroup-fg_fm_1')), findsOneWidget);
    expect(find.text('Ungroup'), findsOneWidget);

    await tester.tap(find.byKey(const Key('face-crop-ungroup-fg_fm_1')));
    await tester.pumpAndSettle();
    expect(persons.ungroupFaceGroupCalls, ['fg_fm_1']);
    expect(find.byKey(const Key('face-crop-facegroup-fg_fm_1')), findsNothing);
    expect(find.byKey(const Key('face-crop-exclusion-ex_g1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-exclusion-ex_g2')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: multi-select drag to Unassigned creates one GroupFM',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_b',
              personId: 'person_1',
              itemId: 'item_b',
              tagId: 'tag_b',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_b']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_a')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_b')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;
    expect(find.byKey(const Key('face-crop-selected-ap_a')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_b')), findsOneWidget);

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_a')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-unassigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Two faces moved together become one GroupFM via a single batched call
    // (R6), not two individual unlinks.
    expect(persons.unlinkCalls, isEmpty);
    expect(persons.unassignAppearancesCalls, hasLength(1));
    expect(persons.unassignAppearancesCalls.single.toSet(), {'ap_a', 'ap_b'});
    expect(persons.unassignedAppearances.map((a) => a.id).toSet(), {
      'ap_a',
      'ap_b',
    });
    final moved =
        persons.unassignedAppearances.where((a) => a.id == 'ap_a').single;
    expect(moved.faceGroupId, isNotNull);
    expect(moved.faceGroupKind, FaceGroupKind.fm);
  });

  testWidgets(
      'face crop trays: FaceGroup shows Set name; naming promotes to Assigned',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_a',
        personId: null,
        faceGroupId: 'fg_1',
        faceGroupKind: FaceGroupKind.fa,
        itemId: 'item_a',
        tagId: 'tag_a',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_b',
        personId: null,
        faceGroupId: 'fg_1',
        faceGroupKind: FaceGroupKind.fa,
        itemId: 'item_b',
        tagId: 'tag_b',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_b']),
          ),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-unassigned')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('face-crop-facegroup-set-name-fg_1')),
      findsOneWidget,
    );
    // Grouped faces promote as a whole via Set name — no per-face Set name.
    expect(find.byKey(const Key('face-crop-set-name-ap_a')), findsNothing);
    expect(find.byKey(const Key('face-crop-set-name-ap_b')), findsNothing);

    await tester.tap(
      find.byKey(const Key('face-crop-facegroup-set-name-fg_1')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-name-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('person-name-field')),
      'Sam',
    );
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(persons.assignFaceGroupCalls, hasLength(1));
    expect(persons.assignFaceGroupCalls.single.faceGroupId, 'fg_1');
    expect(persons.assignFaceGroupCalls.single.name, 'Sam');

    // After naming, the whole group moves to Assigned under the new person;
    // the FaceGroup is gone from Unassigned (server deletes it, R6).
    expect(find.byKey(const Key('face-crop-facegroup-fg_1')), findsNothing);
    expect(find.byKey(const Key('face-crop-person-name')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Sam',
    );
  });

  testWidgets(
      'face crop trays: Remove person moves faces to Unassigned',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-appearance-ap_a')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-set-name-ap_a')), findsNothing);

    await tester.tap(find.byKey(const Key('face-crop-person-unassign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('face-crop-person-unassign-confirm')));
    await tester.pumpAndSettle();

    expect(persons.deleteCalls, ['person_1']);
    expect(persons.unassignedAppearances.map((a) => a.id), ['ap_a']);
    expect(find.byKey(const Key('face-crop-appearance-ap_a')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-set-name-ap_a')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-chrome')), findsNothing);
    expect(find.byKey(const Key('face-crop-assigned-empty')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: folder picker scopes unassigned crops',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_paris',
        personId: null,
        itemId: 'item_paris',
        tagId: 'tag_paris',
      ),
      fixtureAppearance(
        id: 'ap_rome',
        personId: null,
        itemId: 'item_rome',
        tagId: 'tag_rome',
      ),
    ]);
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'item_paris',
          sourceRef: 'file:///albums/Paris/a.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
        fixtureItem(
          id: 'item_rome',
          sourceRef: 'file:///albums/Rome/b.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialLeafFolder: '/albums/Paris'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-appearance-ap_paris')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_rome')), findsNothing);

    await tester.tap(find.byKey(const Key('face-crop-folder-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rome').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-appearance-ap_rome')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_paris')), findsNothing);
  });

  testWidgets(
      'face crop trays: first load selects first in-folder person',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_paris',
              personId: 'person_1',
              itemId: 'item_paris',
              tagId: 'tag_paris',
            ),
            fixtureAppearance(
              id: 'ap_rome',
              personId: 'person_1',
              itemId: 'item_rome',
              tagId: 'tag_rome',
            ),
          ],
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'item_paris',
          sourceRef: 'file:///albums/Paris/a.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
        fixtureItem(
          id: 'item_rome',
          sourceRef: 'file:///albums/Rome/b.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialLeafFolder: '/albums/Paris'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Sam',
    );
    expect(find.byKey(const Key('face-crop-appearance-ap_paris')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_rome')), findsNothing);
  });

  testWidgets(
      'face crop trays: dropdown offers New Person... and in-folder people',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_rome_only',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_rome',
              personId: 'person_rome_only',
              itemId: 'item_rome',
              tagId: 'tag_rome',
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_paris',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_paris',
              personId: 'person_paris',
              itemId: 'item_paris',
              tagId: 'tag_paris',
            ),
          ],
        ),
      ],
    );
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_paris_u',
        tagId: 'tag_u',
      ),
    );
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'item_paris',
          sourceRef: 'file:///albums/Paris/a.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
        fixtureItem(
          id: 'item_paris_u',
          sourceRef: 'file:///albums/Paris/u.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
        fixtureItem(
          id: 'item_rome',
          sourceRef: 'file:///albums/Rome/b.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialLeafFolder: '/albums/Paris'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-person-option-new')), findsOneWidget);
    expect(
      find.byKey(const Key('face-crop-person-option-in-folder-person_paris')),
      findsOneWidget,
    );
    expect(find.text('Sam · in folder'), findsWidgets);
    expect(
      find.byKey(const Key('face-crop-person-option-person_rome_only')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('face-crop-person-option-in-folder-person_rome_only')),
      findsNothing,
    );
    expect(find.text('Person'), findsNothing);
  });

  testWidgets(
      'face crop trays: folder switch selects first in-folder person',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_paris',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_paris',
              personId: 'person_paris',
              itemId: 'item_paris',
              tagId: 'tag_paris',
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_rome_zoe',
          name: 'Zoe',
          appearances: [
            fixtureAppearance(
              id: 'ap_rome_zoe',
              personId: 'person_rome_zoe',
              itemId: 'item_rome',
              tagId: 'tag_rome_zoe',
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_rome_alex',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_rome_alex',
              personId: 'person_rome_alex',
              itemId: 'item_rome',
              tagId: 'tag_rome_alex',
            ),
          ],
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'item_paris',
          sourceRef: 'file:///albums/Paris/a.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
        fixtureItem(
          id: 'item_rome',
          sourceRef: 'file:///albums/Rome/b.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialLeafFolder: '/albums/Paris'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // First load: Sam (only Paris in-folder person).
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Sam',
    );

    await tester.tap(find.byKey(const Key('face-crop-folder-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rome').last);
    await tester.pumpAndSettle();

    // Alex before Zoe by name among Rome in-folder people.
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Alex',
    );
  });

  testWidgets(
      'face crop trays: assigned likeness groups are boxed by person',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_a',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_a1',
              personId: 'person_a',
              itemId: 'item_a1',
              tagId: 'tag_a1',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_a2',
              personId: 'person_a',
              itemId: 'item_a2',
              tagId: 'tag_a2',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_b',
          name: 'Bea',
          appearances: [
            fixtureAppearance(
              id: 'ap_b1',
              personId: 'person_b',
              itemId: 'item_b1',
              tagId: 'tag_b1',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a1', 'item_a2', 'item_b1']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-cluster-person_a')), findsOneWidget);
    // Solo named faces are not boxed as a group.
    expect(find.byKey(const Key('face-crop-cluster-person_b')), findsNothing);
    expect(find.byKey(const Key('face-crop-appearance-ap_a1')), findsOneWidget);
    // Auto-selected person_a — Bea's faces stay out of Assigned.
    expect(find.byKey(const Key('face-crop-appearance-ap_b1')), findsNothing);

    await tester.tap(find.byKey(const Key('face-crop-cluster-header-person_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-selected-ap_a1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_a2')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Assigned shows only the selected named person',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_a',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_a1',
              personId: 'person_a',
              itemId: 'item_a1',
              tagId: 'tag_a1',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_a2',
              personId: 'person_a',
              itemId: 'item_a2',
              tagId: 'tag_a2',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_b',
          name: 'Bea',
          appearances: [
            fixtureAppearance(
              id: 'ap_b1',
              personId: 'person_b',
              itemId: 'item_b1',
              tagId: 'tag_b1',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_b2',
              personId: 'person_b',
              itemId: 'item_b2',
              tagId: 'tag_b2',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a1', 'item_a2', 'item_b1', 'item_b2']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_a'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-cluster-person_a')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-cluster-person_b')), findsNothing);
    expect(find.byKey(const Key('face-crop-appearance-ap_b1')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Alex',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-person-select')),
        matching: find.text('Alex · in folder'),
      ),
      findsOneWidget,
    );

    // Switch via in-folder dropdown option — only Bea's faces.
    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('face-crop-person-option-in-folder-person_b')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-cluster-person_b')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-cluster-person_a')), findsNothing);
    expect(find.byKey(const Key('face-crop-appearance-ap_a1')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Bea',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-person-select')),
        matching: find.text('Bea · in folder'),
      ),
      findsOneWidget,
    );

    // Deep-link / re-open focused on Bea — only her faces.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a1', 'item_a2', 'item_b1', 'item_b2']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(
            key: ValueKey('faces-bea'),
            initialPersonId: 'person_b',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-cluster-person_b')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-cluster-person_a')), findsNothing);
    expect(find.byKey(const Key('face-crop-appearance-ap_a1')), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Bea',
    );
  });

  testWidgets(
      'face crop trays: multi-face FaceGroup lives in Unassigned, not Assigned',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_named',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_n1',
              personId: 'person_named',
              itemId: 'item_n1',
              tagId: 'tag_n1',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_n2',
              personId: 'person_named',
              itemId: 'item_n2',
              tagId: 'tag_n2',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_u1',
        personId: null,
        faceGroupId: 'fg_u',
        faceGroupKind: FaceGroupKind.fa,
        itemId: 'item_u1',
        tagId: 'tag_u1',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_u2',
        personId: null,
        faceGroupId: 'fg_u',
        faceGroupKind: FaceGroupKind.fa,
        itemId: 'item_u2',
        tagId: 'tag_u2',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_u1', 'item_u2', 'item_n1', 'item_n2']),
          ),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-unassigned')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_u')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-cluster-person_named')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_u')),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'face crop trays: drag cluster header creates one GroupFM',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_g',
          name: 'Group',
          appearances: [
            fixtureAppearance(
              id: 'ap_g1',
              personId: 'person_g',
              itemId: 'item_g1',
              tagId: 'tag_g1',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_g2',
              personId: 'person_g',
              itemId: 'item_g2',
              tagId: 'tag_g2',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_g1', 'item_g2']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_g'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-cluster-header-person_g')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-unassigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // The whole GroupP cluster moves together — one GroupFM, not per-face
    // unlinks (R6).
    expect(persons.unlinkCalls, isEmpty);
    expect(persons.unassignAppearancesCalls, hasLength(1));
    expect(
      persons.unassignAppearancesCalls.single.toSet(),
      {'ap_g1', 'ap_g2'},
    );
    expect(persons.unassignedAppearances.map((a) => a.id).toSet(), {
      'ap_g1',
      'ap_g2',
    });
    // Last in-folder person emptied → New Person… empty drop target.
    expect(find.text('Drop faces to name a new person'), findsWidgets);
    expect(find.byKey(const Key('face-crop-assigned-empty')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-cluster-person_g')), findsNothing);
    expect(find.textContaining('Grouped faces'), findsOneWidget);
    expect(find.text('Ungroup'), findsOneWidget);
  });

  testWidgets(
      'face crop trays: emptying focused person lands on another in-folder person',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_a',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_a',
              itemId: 'item_a',
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_b',
          name: 'Bea',
          appearances: [
            fixtureAppearance(
              id: 'ap_b',
              personId: 'person_b',
              itemId: 'item_b',
              tagId: 'tag_b',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_b']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_a'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-appearance-ap_a')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_b')), findsNothing);

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_a')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-unassigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    // Land on Bea — not New Person… with everyone's faces.
    expect(find.text('Drop faces to name a new person'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_a')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_b')),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Bea',
    );
  });

  testWidgets(
      'face crop trays: single drag updates Unassigned without full reload flash',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_solo',
              personId: 'person_1',
              itemId: 'item_solo',
              tagId: 'tag_solo',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_solo']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-trays-loading')), findsNothing);

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_solo')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-unassigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    // One frame: optimistic local patch (must not flash full-page loading).
    await tester.pump();

    expect(find.byKey(const Key('face-crop-trays-loading')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-unassigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_solo')),
      ),
      findsOneWidget,
    );
    expect(persons.unlinkCalls, ['ap_solo']);

    await tester.pumpAndSettle();
  });

  testWidgets(
      'face crop trays: leaf folder hidden while ingest loading, then appears',
      (tester) async {
    final items = _itemsInAlbum(['item_a']);
    final persons = FakePersonsRepository(persons: const []);
    var releaseScan = false;
    final ingest = FolderIngestQueue(
      itemsRepository: items,
      jobsRepository: FakeJobsRepository(),
      isUsageBlocked: () => false,
      enumerateFolder: (_) async {
        while (!releaseScan) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        return const [];
      },
      contentHasher: (_) async => 'h',
      perceptualHasher: (_) async => null,
    );
    // Simulate mid-load: items already registered under /albums/Trip, but
    // the ingest job for that root is still active.
    expect(
      await ingest.enqueue('/albums/Trip'),
      FolderIngestEnqueueResult.started,
    );
    expect(ingest.isLoadingPath('/albums/Trip'), isTrue);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
          folderIngestQueueProvider.overrideWith((ref) => ingest),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Folder exists in the library but must not appear in Faces yet.
    expect(find.byKey(const Key('face-crop-folder-select')), findsNothing);
    expect(find.textContaining('Trip'), findsNothing);
    expect(find.byKey(const Key('face-crop-trays-loading')), findsNothing);

    releaseScan = true;
    for (var i = 0; i < 80 && ingest.hasActiveJobs; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpAndSettle();

    expect(ingest.isLoadingPath('/albums/Trip'), isFalse);
    // Job finished → Faces quietly updates the dropdown (no Refresh tap).
    expect(find.byKey(const Key('face-crop-folder-select')), findsOneWidget);
    expect(find.textContaining('Trip'), findsWidgets);
    expect(find.byKey(const Key('face-crop-trays-loading')), findsNothing);
  });

  testWidgets(
      'face crop trays: Refresh adopts new unowned leaf into open collection',
      (tester) async {
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'c1',
            name: 'Grow',
            leafFolders: ['/albums/Trip/Alpha'],
          ),
        ],
        currentCollectionId: 'c1',
      ),
    );
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'a1',
          sourceRef: 'file:///albums/Trip/Alpha/1.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
      ],
    );
    final persons = FakePersonsRepository(persons: const []);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
          collectionsStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialLeafFolder: '/albums/Trip/Alpha'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cols = ProviderScope.containerOf(
      tester.element(find.byType(FaceCropTraysPage)),
    ).read(collectionsControllerProvider);
    if (!cols.loaded) await cols.load();
    if (!cols.sessionReady) {
      expect(await cols.open('c1'), isTrue);
      await tester.pumpAndSettle();
    }

    items.addItem(
      fixtureItem(
        id: 'b1',
        sourceRef: 'file:///albums/Trip/Beta/1.jpg',
        processingStatus: ProcessingStatus.tagged,
        contentHash: null,
      ),
    );
    await tester.tap(find.byKey(const Key('face-crop-trays-refresh')));
    await tester.pumpAndSettle();

    expect(
      cols.current.leafFolders.toSet(),
      containsAll(['/albums/Trip/Alpha', '/albums/Trip/Beta']),
    );
    await tester.tap(find.byKey(const Key('face-crop-folder-select')));
    await tester.pumpAndSettle();
    expect(find.text('Alpha').last, findsOneWidget);
    expect(find.text('Beta').last, findsOneWidget);
  });

  testWidgets(
      'face crop trays: New Person... and in-folder person when unassigned remain',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
            ),
          ],
        ),
      ],
    );
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_u',
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.2,
          xMin: 0.2,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_u']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-person-option-new')), findsOneWidget);
    expect(
      find.byKey(const Key('face-crop-person-option-in-folder-person_1')),
      findsOneWidget,
    );
    expect(find.text('Sam · in folder'), findsWidgets);
  });

  testWidgets(
      'face crop trays: New Person... absent when no unassigned or excluded',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Dropdown still shows the in-folder person; New Person... is gone.
    expect(find.byKey(const Key('face-crop-person-select')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-person-select')),
        matching: find.text('Sam · in folder'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-person-option-new')), findsNothing);
  });

  testWidgets(
      'face crop trays: New Person... and in-folder person when only excluded remain',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
            ),
          ],
        ),
      ],
    );
    persons.accountExclusions.add(
      const WhoExclusion(
        id: 'ex_1',
        itemId: 'item_e',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_e',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_e']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-person-option-new')), findsOneWidget);
    expect(
      find.byKey(const Key('face-crop-person-option-in-folder-person_1')),
      findsOneWidget,
    );
  });

  testWidgets(
      'face crop trays: no named people auto-enters New Person... mode',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_u',
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.2,
          xMin: 0.2,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_u']),
          ),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Drop faces to name a new person'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_u')),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'face crop trays: New Person... then drop prompts name and assigns',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
            ),
          ],
        ),
      ],
    );
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_u',
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.2,
          xMin: 0.2,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
      fixtureAppearance(
        id: 'ap_u2',
        personId: null,
        itemId: 'item_u2',
        tagId: 'tag_u2',
        region: const TagRegion(
          yMin: 0.2,
          xMin: 0.2,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_u', 'item_u2']),
          ),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('face-crop-person-option-new')));
    await tester.pumpAndSettle();

    expect(find.text('Drop faces to name a new person'), findsWidgets);
    expect(find.byKey(const Key('person-name-dialog')), findsNothing);
    // Assigned must be an empty drop target — hide Sam's existing face.
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_a')),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('face-crop-appearance-ap_u')), findsOneWidget);

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_u')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-assigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-name-dialog')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('person-name-field')),
      'Riley',
    );
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(persons.reassignCalls, hasLength(1));
    expect(persons.reassignCalls.single.appearanceId, 'ap_u');
    expect(persons.reassignCalls.single.name, 'Riley');
    expect(persons.unassignedAppearances.map((a) => a.id), ['ap_u2']);
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('face-crop-person-name'))).data,
      'Riley',
    );
    // Closed dropdown shows the new person as in-folder — not stuck on New Person...
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-person-select')),
        matching: find.text('Riley · in folder'),
      ),
      findsOneWidget,
    );
    // Only Riley's faces in Assigned while dropdown shows Riley.
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_u')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_a')),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-person-option-new')), findsOneWidget);
    expect(
      find.byKey(const Key('face-crop-person-option-in-folder-person_1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('face-crop-person-option-in-folder-person_new_1')),
      findsOneWidget,
    );
    // Riley + Sam both listed as in-folder; switch back to Sam.
    expect(find.text('Riley · in folder'), findsWidgets);
    expect(find.text('Sam · in folder'), findsWidgets);
    await tester.tap(
      find.byKey(const Key('face-crop-person-option-in-folder-person_1')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_a')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_u')),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'face crop trays: New Person... drop cancel leaves face Unassigned',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_u',
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.2,
          xMin: 0.2,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_u']),
          ),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Already in create-mode when the folder has no named people.
    expect(find.text('Drop faces to name a new person'), findsWidgets);

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_u')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-assigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-name-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('person-name-skip')));
    await tester.pumpAndSettle();

    expect(persons.reassignCalls, isEmpty);
    expect(persons.unassignedAppearances.map((a) => a.id), ['ap_u']);
    expect(find.text('Drop faces to name a new person'), findsWidgets);
  });

  testWidgets(
      'face crop trays: focus request switches assigned person without remount',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_a',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_a',
              itemId: 'item_a',
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_b',
          name: 'Blake',
          appearances: [
            fixtureAppearance(
              id: 'ap_b',
              personId: 'person_b',
              itemId: 'item_b',
              tagId: 'tag_b',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );

    ProviderContainer? container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(
            _itemsInAlbum(['item_a', 'item_b']),
          ),
        ],
        child: Builder(
          builder: (context) {
            container ??= ProviderScope.containerOf(context);
            return const MaterialApp(
              home: FaceCropTraysPage(initialPersonId: 'person_a'),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Alex'), findsWidgets);

    container!.read(faceCropFocusRequestProvider.notifier).state =
        const FaceCropFocusRequest(personId: 'person_b', nonce: 1);
    await tester.pumpAndSettle();

    expect(find.text('Blake'), findsWidgets);
    expect(find.byKey(const Key('face-crop-appearance-ap_b')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Unassigned FaceGroup drag to Excluded stays boxed',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_a',
        personId: null,
        faceGroupId: 'fg_1',
        faceGroupKind: FaceGroupKind.fa,
        itemId: 'item_a',
        tagId: 'tag_a',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_b',
        personId: null,
        faceGroupId: 'fg_1',
        faceGroupKind: FaceGroupKind.fa,
        itemId: 'item_b',
        tagId: 'tag_b',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);
    final items = _itemsInAlbum(['item_a', 'item_b'], linkedPersons: persons);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-unassigned')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_1')),
      ),
      findsOneWidget,
    );

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-facegroup-header-fg_1')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-excluded')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.unassignedAppearances, isEmpty);
    expect(persons.accountExclusions, hasLength(2));
    expect(
      persons.accountExclusions.map((e) => e.faceGroupId).toSet(),
      {'fg_1'},
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-excluded')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_1')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-unassigned')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_1')),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'face crop trays: Assigned multi-drag to Excluded mints GroupFM and boxes',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_1',
              itemId: 'item_a',
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_b',
              personId: 'person_1',
              itemId: 'item_b',
              tagId: 'tag_b',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
    final items = _itemsInAlbum(['item_a', 'item_b'], linkedPersons: persons);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_a')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_b')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_a')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-excluded')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.unassignAppearancesCalls, hasLength(1));
    expect(persons.unassignAppearancesCalls.single.toSet(), {'ap_a', 'ap_b'});
    expect(persons.accountExclusions, hasLength(2));
    final fgIds = persons.accountExclusions.map((e) => e.faceGroupId).toSet();
    expect(fgIds.length, 1);
    expect(fgIds.single, isNotNull);
    expect(
      persons.accountExclusions.every((e) => e.faceGroupKind == FaceGroupKind.fm),
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-excluded')),
        matching: find.byKey(Key('face-crop-facegroup-${fgIds.single}')),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Grouped faces'), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Unassigned loose multi-drag to Excluded stays loose + selected',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_u1',
        personId: null,
        itemId: 'item_u1',
        tagId: 'tag_u1',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_u2',
        personId: null,
        itemId: 'item_u2',
        tagId: 'tag_u2',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);
    final items = _itemsInAlbum(['item_u1', 'item_u2'], linkedPersons: persons);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u1')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u2')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_u1')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-excluded')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.unassignAppearancesCalls, isEmpty);
    expect(persons.accountExclusions, hasLength(2));
    expect(
      persons.accountExclusions.every((e) => e.faceGroupId == null),
      isTrue,
    );
    expect(
      find.byKey(Key('face-crop-selected-${_exclusionIdForTag(persons, 'tag_u1')}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('face-crop-selected-${_exclusionIdForTag(persons, 'tag_u2')}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Excluded loose multi-drag back to Unassigned stays selected',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_u1',
        personId: null,
        itemId: 'item_u1',
        tagId: 'tag_u1',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
      fixtureAppearance(
        id: 'ap_u2',
        personId: null,
        itemId: 'item_u2',
        tagId: 'tag_u2',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    ]);
    final items = _itemsInAlbum(['item_u1', 'item_u2'], linkedPersons: persons);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> dragSelection({
      required Key fromKey,
      required Key toTray,
    }) async {
      final from = tester.getCenter(find.byKey(fromKey));
      final to = tester.getCenter(find.byKey(toTray));
      final gesture = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(to);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // Unassigned → Excluded (stay selected).
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u1')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u2')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;
    await dragSelection(
      fromKey: const Key('face-crop-appearance-ap_u1'),
      toTray: const Key('face-crop-tray-excluded'),
    );
    final exclU1 = _exclusionIdForTag(persons, 'tag_u1');
    final exclU2 = _exclusionIdForTag(persons, 'tag_u2');
    expect(
      find.byKey(Key('face-crop-selected-$exclU1')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('face-crop-selected-$exclU2')),
      findsOneWidget,
    );

    // Excluded → Unassigned: faces restored and stay multi-selected.
    await dragSelection(
      fromKey: Key('face-crop-exclusion-$exclU1'),
      toTray: const Key('face-crop-tray-unassigned'),
    );
    expect(persons.accountExclusions, isEmpty);
    expect(persons.unassignedAppearances, hasLength(2));
    final restored1 = _unassignedIdForTag(persons, 'tag_u1');
    final restored2 = _unassignedIdForTag(persons, 'tag_u2');
    expect(find.byKey(Key('face-crop-selected-$restored1')), findsOneWidget);
    expect(find.byKey(Key('face-crop-selected-$restored2')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);

    // Second round-trip: faces must not disappear.
    await dragSelection(
      fromKey: Key('face-crop-appearance-$restored1'),
      toTray: const Key('face-crop-tray-excluded'),
    );
    expect(persons.accountExclusions, hasLength(2));
    final exclU1b = _exclusionIdForTag(persons, 'tag_u1');
    await dragSelection(
      fromKey: Key('face-crop-exclusion-$exclU1b'),
      toTray: const Key('face-crop-tray-unassigned'),
    );
    expect(persons.accountExclusions, isEmpty);
    expect(persons.unassignedAppearances, hasLength(2));
    final restored1b = _unassignedIdForTag(persons, 'tag_u1');
    final restored2b = _unassignedIdForTag(persons, 'tag_u2');
    expect(find.byKey(Key('face-crop-selected-$restored1b')), findsOneWidget);
    expect(find.byKey(Key('face-crop-selected-$restored2b')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: Assigned solo multi-drag to Excluded stays loose + selected',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_a',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_a1',
              personId: 'person_a',
              itemId: 'item_a1',
              tagId: 'tag_a1',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_a2',
              personId: 'person_a',
              itemId: 'item_a2',
              tagId: 'tag_a2',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_b',
          name: 'Bea',
          appearances: [
            fixtureAppearance(
              id: 'ap_b',
              personId: 'person_b',
              itemId: 'item_b',
              tagId: 'tag_b',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
    final items = _itemsInAlbum(
      ['item_a1', 'item_a2', 'item_b'],
      linkedPersons: persons,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Auto-focuses first in-folder person (Alex); same-person Cmd+multi.
    expect(find.byKey(const Key('face-crop-appearance-ap_a1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_b')), findsNothing);
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_a2')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_a1')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-excluded')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.unlinkCalls, isEmpty);
    expect(persons.unassignAppearancesCalls, hasLength(1));
    expect(persons.accountExclusions, hasLength(2));
    // Same-person ≥2 Assigned → Excluded mints GroupFM (not loose).
    final fgIds = persons.accountExclusions
        .map((e) => e.faceGroupId)
        .whereType<String>()
        .toSet();
    expect(fgIds, hasLength(1));
    expect(
      find.byKey(Key('face-crop-facegroup-${fgIds.single}')),
      findsOneWidget,
    );
  });

  testWidgets(
      'face crop trays: Assigned solo multi-drag to Unassigned stays loose + selected',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_a',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_a1',
              personId: 'person_a',
              itemId: 'item_a1',
              tagId: 'tag_a1',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
            fixtureAppearance(
              id: 'ap_a2',
              personId: 'person_a',
              itemId: 'item_a2',
              tagId: 'tag_a2',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_b',
          name: 'Bea',
          appearances: [
            fixtureAppearance(
              id: 'ap_b',
              personId: 'person_b',
              itemId: 'item_b',
              tagId: 'tag_b',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
    final items = _itemsInAlbum(
      ['item_a1', 'item_a2', 'item_b'],
      linkedPersons: persons,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_a1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_a2')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_a1')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-unassigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.unlinkCalls, isEmpty);
    expect(persons.unassignAppearancesCalls, hasLength(1));
    expect(persons.unassignAppearancesCalls.single.toSet(), {'ap_a1', 'ap_a2'});
    // Same-person ≥2 → one GroupFM in Unassigned.
    final fgIds = persons.unassignedAppearances
        .map((a) => a.faceGroupId)
        .whereType<String>()
        .toSet();
    expect(fgIds, hasLength(1));
    expect(persons.unassignedAppearances, hasLength(2));
    expect(
      find.byKey(Key('face-crop-facegroup-${fgIds.single}')),
      findsOneWidget,
    );
  });

  testWidgets(
      'face crop trays: auto-selects first person; drop assigns without Select a person',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_b',
          name: 'Bea',
          appearances: [
            fixtureAppearance(
              id: 'ap_b',
              personId: 'person_b',
              itemId: 'item_b',
              tagId: 'tag_b',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_a',
          name: 'Alex',
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_a',
              itemId: 'item_a',
              tagId: 'tag_a',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.4,
                xMax: 0.4,
              ),
            ),
          ],
        ),
      ],
    );
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_u',
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.1,
          xMin: 0.1,
          yMax: 0.4,
          xMax: 0.4,
        ),
      ),
    );
    final items = _itemsInAlbum(
      ['item_a', 'item_b', 'item_u'],
      linkedPersons: persons,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(home: FaceCropTraysPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Name-sorted first in-folder person is Alex (not overview / Select a person).
    expect(find.text('Select a person'), findsNothing);
    expect(
      find.byKey(const Key('face-crop-person-select-label-person_a')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-appearance-ap_a')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_b')), findsNothing);

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_u')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-assigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.textContaining('Select a person before assigning'), findsNothing);
    expect(persons.unassignedAppearances, isEmpty);
    expect(
      persons.personDetails
          .expand((p) => p.appearances)
          .where((a) => a.personId == 'person_a')
          .length,
      2,
    );
  });

  testWidgets(
      'face crop trays: Excluded FaceGroup drag to Assigned uses assignFaceGroup',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: const [],
        ),
      ],
    );
    persons.accountExclusions.addAll([
      const WhoExclusion(
        id: 'excl_a',
        itemId: 'item_a',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_a',
        createdAt: '2026-07-26T00:00:00.000Z',
        faceGroupId: 'fg_ex',
        faceGroupKind: FaceGroupKind.fm,
      ),
      const WhoExclusion(
        id: 'excl_b',
        itemId: 'item_b',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_b',
        createdAt: '2026-07-26T00:00:00.000Z',
        faceGroupId: 'fg_ex',
        faceGroupKind: FaceGroupKind.fm,
      ),
    ]);
    final items = _itemsInAlbum(['item_a', 'item_b'], linkedPersons: persons);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-excluded')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_ex')),
      ),
      findsOneWidget,
    );

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-facegroup-header-fg_ex')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-assigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.assignFaceGroupCalls, hasLength(1));
    expect(persons.assignFaceGroupCalls.single.faceGroupId, 'fg_ex');
    expect(persons.assignFaceGroupCalls.single.personId, 'person_1');
    expect(persons.reassignCalls, isEmpty);
    expect(persons.accountExclusions, isEmpty);
  });

  testWidgets(
      'face crop trays: collection open filters folder dropdown; no collection menu',
      (tester) async {
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'collection_europe',
            name: 'Europe',
            leafFolders: ['/albums/Paris'],
          ),
        ],
      ),
    );

    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_paris',
              personId: 'person_1',
              itemId: 'item_paris',
              tagId: 'tag_paris',
            ),
            fixtureAppearance(
              id: 'ap_rome',
              personId: 'person_1',
              itemId: 'item_rome',
              tagId: 'tag_rome',
            ),
          ],
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [
        fixtureItem(
          id: 'item_paris',
          sourceRef: 'file:///albums/Paris/a.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
        fixtureItem(
          id: 'item_rome',
          sourceRef: 'file:///albums/Rome/b.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
          collectionsStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialLeafFolder: '/albums/Paris'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cols = ProviderScope.containerOf(
      tester.element(find.byType(FaceCropTraysPage)),
    ).read(collectionsControllerProvider);
    if (!cols.loaded) await cols.load();
    expect(await cols.open('collection_europe'), isTrue);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-collection-menu')), findsNothing);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('face-crop-collection-label')))
          .data,
      'Europe',
    );

    await tester.tap(find.byKey(const Key('face-crop-folder-select')));
    await tester.pumpAndSettle();
    expect(find.text('Paris').last, findsOneWidget);
    expect(find.text('Rome'), findsNothing);
  });

  testWidgets(
      'face crop trays: assign still works with named collection open',
      (tester) async {
    final store = MemoryCollectionsStore(
      const CollectionsFile(
        collections: [
          Collection(
            id: 'collection_trip',
            name: 'Trip',
            leafFolders: ['/albums/Trip'],
          ),
        ],
      ),
    );

    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_1',
          name: 'Sam',
          appearances: const [],
        ),
      ],
    );
    persons.unassignedAppearances.add(
      fixtureAppearance(
        id: 'ap_u',
        personId: null,
        itemId: 'item_u',
        tagId: 'tag_u',
        region: const TagRegion(
          yMin: 0.2,
          xMin: 0.2,
          yMax: 0.5,
          xMax: 0.5,
        ),
      ),
    );
    final items = _itemsInAlbum(['item_u'], linkedPersons: persons);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          personsRepositoryProvider.overrideWithValue(persons),
          itemsRepositoryProvider.overrideWithValue(items),
          collectionsStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cols = ProviderScope.containerOf(
      tester.element(find.byType(FaceCropTraysPage)),
    ).read(collectionsControllerProvider);
    if (!cols.loaded) await cols.load();
    expect(await cols.open('collection_trip'), isTrue);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('face-crop-collection-label')))
          .data,
      'Trip',
    );

    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_u')),
    );
    final to = tester.getCenter(
      find.byKey(const Key('face-crop-tray-assigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.reassignCalls, isNotEmpty);
    expect(persons.reassignCalls.last.personId, 'person_1');
  });
}
