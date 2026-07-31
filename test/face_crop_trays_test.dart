import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/face_crop_trays_page.dart';

import 'fake_items_repository.dart';
import 'fake_persons_repository.dart';

Uint8List _solidJpeg() {
  final image = img.Image(width: 120, height: 120);
  img.fill(image, color: img.ColorRgb8(180, 90, 40));
  return Uint8List.fromList(img.encodeJpg(image));
}

FakeItemsRepository _itemsInAlbum(
  List<String> itemIds, {
  String album = 'Trip',
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
  );
}

void main() {
  setUp(() {
    faceCropLastLeafFolder = null;
    debugFaceCropMetaPressed = null;
  });

  tearDown(() {
    debugFaceCropMetaPressed = null;
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
      find.text('not yet named — includes Unnamed likeness groups'),
      findsOneWidget,
    );
    expect(find.text('faces should not be assigned to a person'), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_u')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-new-person-ap_u')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-exclusion-ex_1')), findsOneWidget);
    expect(
      find.byKey(const Key('face-crop-appearance-ap_assigned')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('face-crop-new-person-ap_assigned')),
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
    expect(find.byKey(const Key('face-crop-person-select')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: switching to unnamed person clears rename field',
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
          id: 'person_unnamed',
          name: null,
          appearances: [
            fixtureAppearance(
              id: 'ap_unnamed',
              personId: 'person_unnamed',
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

    // Unnamed solos live in Unassigned (not the Assigned person dropdown).
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_unnamed')));
    await tester.pumpAndSettle();

    expect(find.text('Set name'), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-rename')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('face-crop-person-rename')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets(
      'face crop trays: named + Rename do not linger onto unnamed person',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_named',
          name: 'Sam',
          appearances: [
            fixtureAppearance(
              id: 'ap_c',
              personId: 'person_named',
              itemId: 'item_a',
              tagId: 'tag_a',
            ),
          ],
        ),
        fixturePersonDetail(
          id: 'person_unnamed',
          name: null,
          appearances: [
            fixtureAppearance(
              id: 'ap_u',
              personId: 'person_unnamed',
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

    expect(find.text('Sam'), findsWidgets);
    expect(find.byKey(const Key('face-crop-person-rename-start')), findsOneWidget);

    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-person-rename-done')), findsOneWidget);
    expect(find.text('Set name'), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-rename-start')), findsNothing);
  });

  testWidgets(
      'face crop trays: New person from unassigned crop',
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

    await tester.tap(find.byKey(const Key('face-crop-new-person-ap_u')));
    await tester.pumpAndSettle();

    expect(persons.reassignCalls, hasLength(1));
    expect(persons.reassignCalls.single.appearanceId, 'ap_u');
    expect(persons.reassignCalls.single.personId, isNull);
    expect(persons.unassignedAppearances, isEmpty);
    expect(find.byKey(const Key('face-crop-appearance-ap_u')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(find.text('Set name'), findsOneWidget);
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

    // Tap bottom-left — New person icon covers the top-right / near-center.
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
      'face crop trays: multi-select drag to Unassigned unlinks all',
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

    expect(persons.unlinkCalls.toSet(), {'ap_a', 'ap_b'});
    expect(persons.unassignedAppearances.map((a) => a.id).toSet(), {
      'ap_a',
      'ap_b',
    });
  });

  testWidgets(
      'face crop trays: unnamed group in Unassigned shows Set name not New person',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_unnamed',
          name: null,
          appearances: [
            fixtureAppearance(
              id: 'ap_a',
              personId: 'person_unnamed',
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
              personId: 'person_unnamed',
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
          home: FaceCropTraysPage(initialPersonId: 'person_unnamed'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-cluster-person_unnamed')), findsOneWidget);
    expect(find.textContaining('Unnamed'), findsWidgets);
    expect(find.text('Set name'), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-rename')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-new-person-ap_a')), findsNothing);
    expect(find.byKey(const Key('face-crop-new-person-ap_b')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('face-crop-person-rename')),
      'Sam',
    );
    await tester.tap(find.byKey(const Key('face-crop-person-rename-done')));
    await tester.pumpAndSettle();

    expect(persons.renameCalls, hasLength(1));
    expect(persons.renameCalls.single.personId, 'person_unnamed');
    expect(persons.renameCalls.single.name, 'Sam');
    // After naming, the multi-face group moves to Assigned.
    expect(find.byKey(const Key('face-crop-cluster-person_unnamed')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-cluster-person_unnamed')),
      ),
      findsOneWidget,
    );
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
    expect(find.byKey(const Key('face-crop-new-person-ap_a')), findsNothing);

    await tester.tap(find.byKey(const Key('face-crop-person-unassign')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('face-crop-person-unassign-confirm')));
    await tester.pumpAndSettle();

    expect(persons.deleteCalls, ['person_1']);
    expect(persons.unassignedAppearances.map((a) => a.id), ['ap_a']);
    expect(find.byKey(const Key('face-crop-appearance-ap_a')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-new-person-ap_a')), findsOneWidget);
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
      'face crop trays: person dropdown marks people in current folder',
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

    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('face-crop-person-option-in-folder-person_paris')),
      findsOneWidget,
    );
    expect(find.text('Sam · in folder'), findsWidgets);
    expect(
      find.byKey(const Key('face-crop-person-option-person_rome_only')),
      findsOneWidget,
    );
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Alex · in folder'), findsNothing);
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
    expect(find.byKey(const Key('face-crop-appearance-ap_b1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('face-crop-cluster-header-person_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-selected-ap_a1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_a2')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-selected-ap_b1')), findsNothing);
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
  });

  testWidgets(
      'face crop trays: unnamed multi-face group lives in Unassigned',
      (tester) async {
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'person_u',
          name: null,
          appearances: [
            fixtureAppearance(
              id: 'ap_u1',
              personId: 'person_u',
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
              personId: 'person_u',
              itemId: 'item_u2',
              tagId: 'tag_u2',
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
        matching: find.byKey(const Key('face-crop-cluster-person_u')),
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
        matching: find.byKey(const Key('face-crop-cluster-person_u')),
      ),
      findsNothing,
    );
  });

  testWidgets(
      'face crop trays: drag cluster header unlinks all faces in group',
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

    expect(persons.unlinkCalls.toSet(), {'ap_g1', 'ap_g2'});
    expect(persons.unassignedAppearances.map((a) => a.id).toSet(), {
      'ap_g1',
      'ap_g2',
    });
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
}
