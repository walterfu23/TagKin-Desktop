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

String _assignedIdForTag(FakePersonsRepository persons, String tagId) {
  for (final p in persons.personDetails) {
    for (final a in p.appearances) {
      if (a.tagId == tagId && a.personId != null) return a.id;
    }
  }
  fail('No assigned appearance for tag $tagId');
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
      find.byKey(Key('face-crop-selected-${_unassignedIdForTag(persons, 'tag_e1')}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('face-crop-selected-${_unassignedIdForTag(persons, 'tag_e2')}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('face-crop-selected-${_unassignedIdForTag(persons, 'tag_e3')}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

    expect(persons.accountExclusions, hasLength(3));
    expect(persons.unassignedAppearances, isEmpty);
    expect(
      find.byKey(Key('face-crop-selected-${_exclusionIdForTag(persons, 'tag_e1')}')),
      findsOneWidget,
      reason: 'Cmd+Z should restore Excluded multi-select',
    );
    expect(
      find.byKey(Key('face-crop-selected-${_exclusionIdForTag(persons, 'tag_e2')}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('face-crop-selected-${_exclusionIdForTag(persons, 'tag_e3')}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    await _cmdY(tester);

    expect(persons.accountExclusions, isEmpty);
    expect(persons.unassignedAppearances, hasLength(3));
    expect(
      find.byKey(Key('face-crop-selected-${_unassignedIdForTag(persons, 'tag_e1')}')),
      findsOneWidget,
      reason: 'Cmd+Y should restore Unassigned multi-select',
    );
    expect(
      find.byKey(Key('face-crop-selected-${_unassignedIdForTag(persons, 'tag_e2')}')),
      findsOneWidget,
    );
    expect(
      find.byKey(Key('face-crop-selected-${_unassignedIdForTag(persons, 'tag_e3')}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
  });

  testWidgets(
      'Excluded bystander selection restored after inbound drop Cmd+Z',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(persons: const []);
    persons.accountExclusions.addAll([
      const WhoExclusion(
        id: 'excl_a',
        itemId: 'item_a',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_a',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
      const WhoExclusion(
        id: 'excl_b',
        itemId: 'item_b',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_b',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    ]);
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_a', 'item_b', 'item_u'],
    );

    // Select two Excluded faces (not the one about to move).
    await tester.tap(find.byKey(const Key('face-crop-exclusion-excl_a')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-exclusion-excl_b')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);

    // Inbound single drop into Excluded clears selection.
    final from = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_u')),
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

    expect(persons.accountExclusions, hasLength(3));
    expect(find.byKey(const Key('face-crop-group-selection')), findsNothing);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

    expect(persons.accountExclusions, hasLength(2));
    expect(persons.unassignedAppearances, hasLength(1));
    expect(
      find.byKey(Key('face-crop-selected-${_exclusionIdForTag(persons, 'tag_a')}')),
      findsOneWidget,
      reason: 'Cmd+Z should restore the pre-drop Excluded selection',
    );
    expect(
      find.byKey(Key('face-crop-selected-${_exclusionIdForTag(persons, 'tag_b')}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);

    await _cmdY(tester);

    expect(persons.accountExclusions, hasLength(3));
    expect(find.byKey(const Key('face-crop-group-selection')), findsNothing);
  });

  testWidgets(
      'Inbound exclude then outbound hop: stacked Cmd+Z does not 404',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final persons = FakePersonsRepository(persons: const []);
    persons.accountExclusions.addAll([
      const WhoExclusion(
        id: 'excl_a',
        itemId: 'item_a',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_a',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
      const WhoExclusion(
        id: 'excl_b',
        itemId: 'item_b',
        region: TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4),
        createdFromTagId: 'tag_b',
        createdAt: '2026-07-26T00:00:00.000Z',
      ),
    ]);
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_a', 'item_b', 'item_u'],
    );

    // Select face1+face2 in Excluded (bystanders for the inbound drop).
    await tester.tap(find.byKey(const Key('face-crop-exclusion-excl_a')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-exclusion-excl_b')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    // face3 Unassigned → Excluded (undo entry A).
    final fromU = tester.getCenter(
      find.byKey(const Key('face-crop-appearance-ap_u')),
    );
    final toExcluded = tester.getCenter(
      find.byKey(const Key('face-crop-tray-excluded')),
    );
    var gesture = await tester.startGesture(fromU);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(toExcluded);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.accountExclusions, hasLength(3));
    expect(persons.unassignedAppearances, isEmpty);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    // Remint face3's exclusion id (createWhoExclusion-class remint). Entry A's
    // frozen id would 404 on the second Cmd+Z without tagId resolve.
    final face3Idx = persons.accountExclusions.indexWhere(
      (e) => e.createdFromTagId == 'tag_u',
    );
    expect(face3Idx, greaterThanOrEqualTo(0));
    final face3 = persons.accountExclusions[face3Idx];
    persons.accountExclusions[face3Idx] = WhoExclusion(
      id: 'excl_tag_u_reminted',
      itemId: face3.itemId,
      region: face3.region,
      createdFromTagId: face3.createdFromTagId,
      createdAt: face3.createdAt,
      faceGroupId: face3.faceGroupId,
      faceGroupKind: face3.faceGroupKind,
    );

    // face1 Excluded → Unassigned (undo entry B).
    final fromA = tester.getCenter(
      find.byKey(const Key('face-crop-exclusion-excl_a')),
    );
    final toUnassigned = tester.getCenter(
      find.byKey(const Key('face-crop-tray-unassigned')),
    );
    gesture = await tester.startGesture(fromA);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(toUnassigned);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.unassignedAppearances, hasLength(1));
    expect(persons.accountExclusions, hasLength(2));

    // Cmd+Z undoes B — face1 back to Excluded.
    await _cmdZ(tester);
    expect(
      persons.accountExclusions.where((e) => e.createdFromTagId == 'tag_a'),
      hasLength(1),
    );
    expect(persons.unassignedAppearances, isEmpty);
    expect(find.textContaining('Not found'), findsNothing);
    expect(find.textContaining('Item not found'), findsNothing);

    // Cmd+Z undoes A — face3 back to Unassigned (must resolve reminted id).
    await _cmdZ(tester);
    expect(
      persons.accountExclusions.where((e) => e.createdFromTagId == 'tag_u'),
      isEmpty,
    );
    expect(persons.unassignedAppearances, hasLength(1));
    expect(persons.unassignedAppearances.single.tagId, 'tag_u');
    expect(
      persons.accountExclusions.where((e) => e.createdFromTagId == 'tag_a'),
      hasLength(1),
    );
    expect(
      persons.accountExclusions.where((e) => e.createdFromTagId == 'tag_b'),
      hasLength(1),
    );
    expect(find.textContaining('Not found'), findsNothing);
    expect(find.textContaining('Item not found'), findsNothing);
  });

  testWidgets(
      'Unassigned→Excluded undo/redo remint cycle does not 404',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_u1', 'item_u2'],
    );

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

    expect(persons.accountExclusions, hasLength(2));
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    // undo → redo remints exclusion ids; second undo must use live ids.
    await _cmdZ(tester);
    expect(persons.accountExclusions, isEmpty);
    expect(persons.unassignedAppearances, hasLength(2));
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    await _cmdY(tester);
    expect(persons.accountExclusions, hasLength(2));
    expect(persons.unassignedAppearances, isEmpty);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);
    expect(persons.accountExclusions, isEmpty);
    expect(persons.unassignedAppearances, hasLength(2));
    expect(find.byKey(const Key('undo-depth')), findsNothing);
    expect(find.textContaining('Item not found'), findsNothing);
    expect(find.textContaining('Not found'), findsNothing);
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

  testWidgets(
      'Unassigned→Assigned multi-drop Cmd+Z restores Unassigned selection',
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_a', 'item_u1', 'item_u2'],
      initialPersonId: 'person_1',
    );

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
      find.byKey(const Key('face-crop-tray-assigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(persons.unassignedAppearances, isEmpty);
    expect(
      persons.personDetails
          .expand((p) => p.appearances)
          .where((a) => a.personId == 'person_1')
          .length,
      greaterThanOrEqualTo(3),
    );
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);
    // Forward assign clears loose multi-select.
    expect(find.byKey(const Key('face-crop-group-selection')), findsNothing);

    await _cmdZ(tester);

    expect(persons.unassignedAppearances, hasLength(2));
    expect(
      find.byKey(Key('face-crop-selected-${_unassignedIdForTag(persons, 'tag_u1')}')),
      findsOneWidget,
      reason: 'Cmd+Z should reselect faces in Unassigned',
    );
    expect(
      find.byKey(Key('face-crop-selected-${_unassignedIdForTag(persons, 'tag_u2')}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    await _cmdY(tester);

    expect(persons.unassignedAppearances, isEmpty);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);
    expect(
      find.byKey(Key('face-crop-selected-${_assignedIdForTag(persons, 'tag_u1')}')),
      findsOneWidget,
      reason: 'Cmd+Y should reselect faces under Assigned',
    );
    expect(
      find.byKey(Key('face-crop-selected-${_assignedIdForTag(persons, 'tag_u2')}')),
      findsOneWidget,
    );
  });

  testWidgets(
      'Unassigned→Assigned Cmd+Z then Group forms GroupFM',
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_a', 'item_u1', 'item_u2'],
      initialPersonId: 'person_1',
    );

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
      find.byKey(const Key('face-crop-tray-assigned')),
    );
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    await _cmdZ(tester);

    final id1 = _unassignedIdForTag(persons, 'tag_u1');
    final id2 = _unassignedIdForTag(persons, 'tag_u2');
    expect(find.byKey(const Key('face-crop-group-selection')), findsOneWidget);
    await tester.tap(find.byKey(const Key('face-crop-group-selection')));
    await tester.pumpAndSettle();

    expect(persons.assembleAppearancesCalls, hasLength(1));
    expect(persons.assembleAppearancesCalls.single.toSet(), {id1, id2});
    expect(
      find.byKey(const Key('face-crop-facegroup-fg_fm_1')),
      findsOneWidget,
      reason: 'Group after undo restore should mint a GroupFM box',
    );
  });

  testWidgets(
      'Group faces Cmd+Z / Cmd+Y remint cycle does not 404',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_u1', 'item_u2'],
    );

    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u1')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u2')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    await tester.tap(find.byKey(const Key('face-crop-group-selection')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-facegroup-fg_fm_1')), findsOneWidget);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);
    expect(
      persons.unassignedAppearances.every((a) => a.faceGroupId == null),
      isTrue,
      reason: 'Cmd+Z should dissolve GroupFM',
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    await _cmdY(tester);
    final remintedFg = persons.unassignedAppearances
        .map((a) => a.faceGroupId)
        .whereType<String>()
        .toSet();
    expect(remintedFg, hasLength(1));
    expect(
      find.byKey(Key('face-crop-facegroup-${remintedFg.single}')),
      findsOneWidget,
      reason: 'Cmd+Y should remint a GroupFM',
    );

    // Second undo must use live FaceGroup id (not the first assemble's id).
    await _cmdZ(tester);
    expect(
      persons.unassignedAppearances.every((a) => a.faceGroupId == null),
      isTrue,
      reason: 'Second Cmd+Z after remint must not 404',
    );
    expect(persons.unassignedAppearances, hasLength(2));
  });

  testWidgets(
      'Group then Ungroup then two Cmd+Z remint stack does not 404',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_u1', 'item_u2'],
    );

    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u1')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = () => true;
    await tester.tap(find.byKey(const Key('face-crop-appearance-ap_u2')));
    await tester.pumpAndSettle();
    debugFaceCropMetaPressed = null;

    await tester.tap(find.byKey(const Key('face-crop-group-selection')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('face-crop-facegroup-fg_fm_1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('face-crop-ungroup-fg_fm_1')));
    await tester.pumpAndSettle();
    expect(
      persons.unassignedAppearances.every((a) => a.faceGroupId == null),
      isTrue,
    );
    // Stack: Ungroup (top) then Group.
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    // Undo Ungroup → remints GroupFM (not fg_fm_1).
    await _cmdZ(tester);
    final restoredFg = persons.unassignedAppearances
        .map((a) => a.faceGroupId)
        .whereType<String>()
        .toSet();
    expect(restoredFg, hasLength(1));
    expect(restoredFg.single, isNot('fg_fm_1'));
    expect(
      find.byKey(Key('face-crop-facegroup-${restoredFg.single}')),
      findsOneWidget,
    );

    // Undo Group → must resolve reminted FaceGroup id, not frozen fg_fm_1.
    await _cmdZ(tester);
    expect(
      persons.unassignedAppearances.every((a) => a.faceGroupId == null),
      isTrue,
      reason: 'Second Cmd+Z (undo Group) must not 404 on reminted FaceGroup',
    );
    expect(persons.unassignedAppearances, hasLength(2));
    expect(find.byKey(const Key('undo-depth')), findsNothing);

    // Full redo: Group remints again; Ungroup must resolve by tagId (not
    // stale redoFaceGroupId from its undo), or Cmd+Y 404s with depth stuck.
    await _cmdY(tester);
    final redoneFg = persons.unassignedAppearances
        .map((a) => a.faceGroupId)
        .whereType<String>()
        .toSet();
    expect(redoneFg, hasLength(1));
    expect(
      find.byKey(Key('face-crop-facegroup-${redoneFg.single}')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdY(tester);
    expect(
      persons.unassignedAppearances.every((a) => a.faceGroupId == null),
      isTrue,
      reason: 'Cmd+Y Ungroup after Group remint must not 404',
    );
    expect(persons.unassignedAppearances, hasLength(2));
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);
  });

  testWidgets(
      'Excluded GroupFM → Assigned Cmd+Z restores FaceGroup; remint cycle ok',
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

    await _pumpFacesUndoHost(
      tester,
      persons: persons,
      itemIds: const ['item_a', 'item_b'],
      initialPersonId: 'person_1',
    );

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
    expect(persons.accountExclusions, isEmpty);
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    await _cmdZ(tester);

    expect(persons.accountExclusions, hasLength(2));
    expect(
      persons.accountExclusions.every((e) => e.faceGroupId != null),
      isTrue,
      reason: 'Cmd+Z should restore Excluded GroupFM, not loose faces',
    );
    final restoredFg = persons.accountExclusions.first.faceGroupId!;
    expect(
      persons.accountExclusions.every((e) => e.faceGroupId == restoredFg),
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('face-crop-tray-excluded')),
        matching: find.byKey(Key('face-crop-facegroup-$restoredFg')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);
    expect(find.textContaining('Item not found'), findsNothing);
    expect(find.textContaining('Face group not found'), findsNothing);

    await _cmdY(tester);
    expect(persons.accountExclusions, isEmpty);
    expect(persons.assignFaceGroupCalls, hasLength(2));
    expect(find.byKey(const Key('undo-depth')), findsOneWidget);

    // Second undo after remint must not 404.
    await _cmdZ(tester);
    expect(persons.accountExclusions, hasLength(2));
    expect(
      persons.accountExclusions.every((e) => e.faceGroupId != null),
      isTrue,
    );
    expect(find.byKey(const Key('undo-depth')), findsNothing);
    expect(find.textContaining('Item not found'), findsNothing);
    expect(find.textContaining('Not found'), findsNothing);
    expect(find.textContaining('Face group not found'), findsNothing);
  });
}

