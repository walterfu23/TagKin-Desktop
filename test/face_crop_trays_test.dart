import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/face_crop_trays_page.dart';

import 'fake_items_repository.dart';
import 'fake_persons_repository.dart';

Uint8List _solidJpeg() {
  final image = img.Image(width: 120, height: 120);
  img.fill(image, color: img.ColorRgb8(180, 90, 40));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
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
          itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
        ],
        child: const MaterialApp(
          home: FaceCropTraysPage(initialPersonId: 'person_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('face-crop-tray-assigned')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-tray-unassigned')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-tray-excluded')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-appearance-ap_u')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-exclusion-ex_1')), findsOneWidget);
    expect(
      find.byKey(const Key('face-crop-appearance-ap_assigned')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-person-chrome')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-name')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-save')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-delete')), findsOneWidget);
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
          itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
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
}
