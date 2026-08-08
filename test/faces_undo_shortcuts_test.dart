import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/face_crop_folder_scope.dart';
import 'package:tagkin_desktop/persons/face_crop_trays_page.dart';
import 'package:tagkin_desktop/undo/undo_shortcuts.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

import 'fake_items_repository.dart';
import 'fake_persons_repository.dart';

FakeItemsRepository _albumItems(
  List<String> ids, {
  FakePersonsRepository? linkedPersons,
}) {
  return FakeItemsRepository(
    items: [
      for (final id in ids)
        fixtureItem(
          id: id,
          sourceRef: 'file:///albums/Trip/$id.jpg',
          processingStatus: ProcessingStatus.tagged,
          contentHash: null,
        ),
    ],
    linkedPersons: linkedPersons,
  );
}

Future<void> _pumpFacesUndoHost(
  WidgetTester tester, {
  required FakePersonsRepository persons,
  required List<String> itemIds,
  String? initialPersonId,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activeTopLevelTabProvider.overrideWith((ref) => TopLevelTab.faces),
        personsRepositoryProvider.overrideWithValue(persons),
        itemsRepositoryProvider.overrideWithValue(
          _albumItems(itemIds, linkedPersons: persons),
        ),
      ],
      child: MaterialApp(
        home: ActiveUndoShortcuts(
          child: SelectableScope(
            child: FaceCropTraysPage(initialPersonId: initialPersonId),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _cmdZ(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.tapAt(
    tester.getTopLeft(find.byType(SelectionArea)) + const Offset(4, 4),
  );
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
  await tester.pumpAndSettle();
}

Future<void> _cmdY(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pump();
  await tester.tapAt(
    tester.getTopLeft(find.byType(SelectionArea)) + const Offset(4, 4),
  );
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
  await tester.pumpAndSettle();
}

/// Regression: Assigned→Unassigned / Set name push D12 undo, and Cmd+Z must
/// reach that stack even when primary focus sits on the app-wide SelectionArea.
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

  testWidgets(
      'Assigned→Unassigned then Cmd+Z reassigns under SelectableScope',
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_a'],
      initialPersonId: 'person_1',
    );

    expect(find.byKey(const Key('undo-depth')), findsNothing);

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

    expect(persons.unlinkCalls, ['ap_a']);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

    expect(
      persons.personDetails
          .expand((p) => p.appearances)
          .any((a) => a.id == 'ap_a' && a.personId == 'person_1'),
      isTrue,
      reason: 'Cmd+Z should reassign the face back to Sam',
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);
  });

  testWidgets(
      'Set name on loose Unassigned face then Cmd+Z restores Unassigned',
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_u'],
    );

    await tester.tap(find.byKey(const Key('face-crop-set-name-ap_u')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('person-name-field')),
      'Riley',
    );
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(persons.unassignedAppearances, isEmpty);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-person-name')), findsOneWidget);

    await _cmdZ(tester);

    expect(persons.unlinkCalls, contains('ap_u'));
    expect(
      persons.unassignedAppearances.any((a) => a.id == 'ap_u'),
      isTrue,
      reason: 'Cmd+Z after Set name should return the face to Unassigned',
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);
  });

  testWidgets(
      'Set name on Unassigned FaceGroup then Cmd+Z restores Unassigned group',
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_a', 'item_b'],
    );

    await tester.tap(
      find.byKey(const Key('face-crop-facegroup-set-name-fg_1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('person-name-field')),
      'Sam',
    );
    await tester.tap(find.byKey(const Key('person-name-save')));
    await tester.pumpAndSettle();

    expect(persons.assignFaceGroupCalls, hasLength(1));
    expect(persons.unassignedAppearances, isEmpty);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

    expect(persons.unassignAppearancesCalls, hasLength(1));
    expect(
      persons.unassignAppearancesCalls.single.toSet(),
      {'ap_a', 'ap_b'},
    );
    expect(
      persons.unassignedAppearances.map((a) => a.id).toSet(),
      {'ap_a', 'ap_b'},
    );
    expect(
      persons.unassignedAppearances.every((a) => a.faceGroupId != null),
      isTrue,
      reason: 'Undo of Set name on a group should restore a FaceGroup',
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);
  });

  testWidgets(
      'Excluded Ungroup then Cmd+Z / Cmd+Y undo-redo FaceGroup',
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
        faceGroupId: 'fg_fm_ex',
        faceGroupKind: FaceGroupKind.fm,
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
      const WhoExclusion(
        id: 'ex_g2',
        itemId: 'item_eg2',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        faceGroupId: 'fg_fm_ex',
        faceGroupKind: FaceGroupKind.fm,
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    ]);

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_eg1', 'item_eg2'],
    );

    expect(
      find.byKey(const Key('face-crop-ungroup-fg_fm_ex')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('face-crop-ungroup-fg_fm_ex')));
    await tester.pumpAndSettle();

    expect(persons.ungroupFaceGroupCalls, ['fg_fm_ex']);
    expect(find.byKey(const Key('face-crop-facegroup-fg_fm_ex')), findsNothing);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

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
      reason: 'Cmd+Z after Excluded Ungroup should restore a FaceGroup box',
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    // Cmd+Y (macOS redo) must re-apply Ungroup — was unbound (beep only).
    await _cmdY(tester);
    expect(persons.ungroupFaceGroupCalls, hasLength(2));
    expect(find.byKey(const Key('face-crop-facegroup-fg_fm_1')), findsNothing);
    expect(find.byKey(const Key('face-crop-exclusion-ex_g1')), findsOneWidget);
    expect(find.byKey(const Key('face-crop-exclusion-ex_g2')), findsOneWidget);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);
  });

  testWidgets(
      'Unassigned Ungroup then Cmd+Z restores FaceGroup',
      (tester) async {
    final persons = FakePersonsRepository(persons: const []);
    persons.unassignedAppearances.addAll([
      fixtureAppearance(
        id: 'ap_g1',
        personId: null,
        faceGroupId: 'fg_fm_u',
        faceGroupKind: FaceGroupKind.fm,
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
        faceGroupId: 'fg_fm_u',
        faceGroupKind: FaceGroupKind.fm,
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_g1', 'item_g2'],
    );

    expect(
      find.byKey(const Key('face-crop-ungroup-fg_fm_u')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('face-crop-ungroup-fg_fm_u')));
    await tester.pumpAndSettle();

    expect(persons.ungroupFaceGroupCalls, ['fg_fm_u']);
    expect(find.byKey(const Key('face-crop-facegroup-fg_fm_u')), findsNothing);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

    expect(persons.assembleAppearancesCalls, hasLength(1));
    expect(
      persons.assembleAppearancesCalls.single.toSet(),
      {'ap_g1', 'ap_g2'},
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-unassigned')),
        matching: find.byKey(const Key('face-crop-facegroup-fg_fm_1')),
      ),
      findsOneWidget,
      reason: 'Cmd+Z after Unassigned Ungroup should restore a FaceGroup box',
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);
  });

  testWidgets(
      'Excluded loose multi-move Cmd+Z / Cmd+Y keeps selection',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(persons: const []);
    persons.accountExclusions.addAll([
      const WhoExclusion(
        id: 'excl_tag_e1',
        itemId: 'item_e1',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_e1',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
      const WhoExclusion(
        id: 'excl_tag_e2',
        itemId: 'item_e2',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_e2',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
      const WhoExclusion(
        id: 'excl_tag_e3',
        itemId: 'item_e3',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_e3',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    ]);

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_e1', 'item_e2', 'item_e3'],
    );

    await tester.tap(find.byKey(const Key('face-crop-exclusion-excl_tag_e1')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-exclusion-excl_tag_e2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('face-crop-exclusion-excl_tag_e3')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

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

    await dragSelection(
      fromKey: const Key('face-crop-exclusion-excl_tag_e1'),
      toTray: const Key('face-crop-tray-unassigned'),
    );

    expect(persons.accountExclusions, isEmpty);
    expect(persons.unassignedAppearances, hasLength(3));
    expect(
      find.byKey(const Key('face-crop-selected-ap_restored_excl_tag_e1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('face-crop-selected-ap_restored_excl_tag_e2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('face-crop-selected-ap_restored_excl_tag_e3')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

    expect(persons.accountExclusions, hasLength(3));
    expect(persons.unassignedAppearances, isEmpty);
    expect(
      find.byKey(const Key('face-crop-selected-excl_tag_e1')),
      findsOneWidget,
      reason: 'Cmd+Z should restore Excluded multi-select',
    );
    expect(
      find.byKey(const Key('face-crop-selected-excl_tag_e2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('face-crop-selected-excl_tag_e3')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    await _cmdY(tester);

    expect(persons.accountExclusions, isEmpty);
    expect(persons.unassignedAppearances, hasLength(3));
    expect(
      find.byKey(const Key('face-crop-selected-ap_restored_excl_tag_e1')),
      findsOneWidget,
      reason: 'Cmd+Y should restore Unassigned multi-select',
    );
    expect(
      find.byKey(const Key('face-crop-selected-ap_restored_excl_tag_e2')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('face-crop-selected-ap_restored_excl_tag_e3')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
  });

  testWidgets(
      'Person → New Person… then Cmd+Z / Cmd+Y restores dropdown',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_a', 'item_u'],
      initialPersonId: 'person_1',
    );

    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-person-select')),
        matching: find.byKey(const Key('face-crop-person-select-label-person_1')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    await tester.tap(find.byKey(const Key('face-crop-person-select')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('face-crop-person-option-new')));
    await tester.pumpAndSettle();

    expect(find.text('Drop faces to name a new person'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_a')),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-person-select')),
        matching: find.byKey(const Key('face-crop-person-select-label-person_1')),
      ),
      findsOneWidget,
      reason: 'Cmd+Z should restore Sam in the Assigned dropdown',
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_a')),
      ),
      findsOneWidget,
    );
    expect(find.text('Drop faces to name a new person'), findsNothing);
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    await _cmdY(tester);

    expect(find.text('Drop faces to name a new person'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-assigned')),
        matching: find.byKey(const Key('face-crop-appearance-ap_a')),
      ),
      findsNothing,
    );
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);
  });
}

