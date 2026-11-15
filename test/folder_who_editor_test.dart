import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/folder_who_editor.dart';
import 'package:tagkin_desktop/undo/undo_controller.dart';

import 'fake_items_repository.dart';
import 'fake_persons_repository.dart';

void main() {
  test('assign reports alike faces on other items', () async {
    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': fixtureKnowledge(item: item)},
    );
    items.assignPersonAlsoMoved = [
      const PersonAppearance(
        id: 'ap_other',
        personId: 'person_maya',
        itemId: 'item_2',
        assignmentState: 'unconfirmed',
        createdAt: '2026-09-29T00:00:00.000Z',
      ),
    ];
    final refreshed = <Set<String>>[];
    final editor = FolderWhoEditor(
      items: items,
      persons: FakePersonsRepository(),
      undo: UndoController(),
      refresh: (ids) async {
        refreshed.add(Set<String>.from(ids));
      },
    );

    final result = await editor.assign(
      itemId: 'item_1',
      tagId: 'tag_who',
      name: 'Maya',
    );

    expect(result.affectedItemIds, {'item_1', 'item_2'});
    expect(result.alsoMoved.single.id, 'ap_other');
    expect(result.snackbar, 'Moved 1 other alike face to Maya as unconfirmed.');
    expect(refreshed.single, {'item_1', 'item_2'});
    expect(items.assignPersonCalls.single.propagateAlike, isNull);
  });

  PersonAppearance holder() => const PersonAppearance(
    id: 'ap_1',
    personId: 'p_maya',
    itemId: 'item_1',
    tagId: 'tag_1',
    createdAt: '2026-09-29T00:00:00.000Z',
  );

  test('assign taking a name unlinks the holder in one undo step', () async {
    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'p_maya',
          name: 'Maya',
          appearances: [holder()],
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      linkedPersons: persons,
      knowledgeByItemId: {'item_1': fixtureKnowledge(item: item)},
    );
    final undo = UndoController();
    final editor = FolderWhoEditor(
      items: items,
      persons: persons,
      undo: undo,
      refresh: (_) async {},
    );

    await editor.assign(
      itemId: 'item_1',
      tagId: 'tag_2',
      personId: 'p_maya',
      takeFrom: holder(),
    );

    expect(persons.unlinkCalls, ['ap_1']);
    expect(items.assignPersonCalls.single.tagId, 'tag_2');
    expect(undo.undoDepth, 1);

    await undo.undo();
    expect(persons.unlinkCalls, ['ap_1', 'ap_assign_tag_2_p_maya']);
    expect(items.assignPersonCalls.last.tagId, 'tag_1');
    expect(items.assignPersonCalls.last.propagateAlike, isFalse);

    await undo.redo();
    expect(persons.unlinkCalls.length, 3);
    expect(items.assignPersonCalls.last.tagId, 'tag_2');
    expect(undo.undoDepth, 1);
  });

  test('a failed assign puts the holder back and records no undo', () async {
    final item = fixtureItem(
      id: 'item_1',
      processingStatus: ProcessingStatus.tagged,
    );
    final persons = FakePersonsRepository(
      persons: [
        fixturePersonDetail(
          id: 'p_maya',
          name: 'Maya',
          appearances: [holder()],
        ),
      ],
    );
    final items = FakeItemsRepository(
      items: [item],
      linkedPersons: persons,
      knowledgeByItemId: {'item_1': fixtureKnowledge(item: item)},
    );
    items.assignPersonError = StateError('boom');
    final undo = UndoController();
    final editor = FolderWhoEditor(
      items: items,
      persons: persons,
      undo: undo,
      refresh: (_) async {},
    );

    await expectLater(
      editor.assign(
        itemId: 'item_1',
        tagId: 'tag_2',
        personId: 'p_maya',
        takeFrom: holder(),
      ),
      throwsStateError,
    );

    expect(persons.unlinkCalls, ['ap_1']);
    // The second call is the attempt to give the holder its name back.
    expect(items.assignPersonCalls.map((c) => c.tagId), ['tag_2', 'tag_1']);
    expect(items.assignPersonCalls.last.propagateAlike, isFalse);
    expect(undo.undoDepth, 0);
  });
}
