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
}
