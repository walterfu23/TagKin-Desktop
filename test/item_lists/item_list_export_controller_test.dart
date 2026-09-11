import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';
import 'package:tagkin_desktop/item_lists/item_list_export_controller.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

void main() {
  test('buildFilter omits empty dimensions and encodes when as ISO', () {
    final repo = FakeItemListsRepository();
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(),
    );
    controller.toggleWho('Sam');
    controller.toggleWhat('swimming');
    controller.setWhenFromDay(DateTime(2020, 1, 15));
    controller.setWhenToDay(DateTime(2020, 2, 1));

    final filter = controller.buildFilter();
    expect(filter.who, ['Sam']);
    expect(filter.what, ['swimming']);
    expect(filter.where, isNull);
    expect(filter.whenFrom, itemListWhenFromIso(DateTime(2020, 1, 15)));
    expect(filter.whenTo, itemListWhenToIso(DateTime(2020, 2, 1)));
  });

  test('reorder updates export CSV order', () async {
    final a = fixtureEntry(itemId: 'a', when: '2020-01-01T00:00:00.000Z');
    final b = fixtureEntry(itemId: 'b', when: '2020-02-01T00:00:00.000Z');
    String? saved;
    final repo = FakeItemListsRepository(list: ItemList(entries: [a, b]));
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(),
      saveCsv: (csv) async {
        saved = csv;
        return '/tmp/item-list.csv';
      },
    );
    await controller.preview();
    expect(controller.entries.map((e) => e.itemId), ['a', 'b']);
    controller.reorder(0, 1);
    expect(controller.entries.map((e) => e.itemId), ['b', 'a']);
    final path = await controller.exportCsv();
    expect(path, '/tmp/item-list.csv');
    expect(saved, contains('b,'));
    final lines = saved!.trimRight().split(RegExp(r'\r?\n'));
    expect(lines[1], startsWith('photo,b,'));
    expect(lines[2], startsWith('photo,a,'));
  });

  test('removeAt drops the row from CSV export', () async {
    final a = fixtureEntry(itemId: 'a', when: '2020-01-01T00:00:00.000Z');
    final b = fixtureEntry(itemId: 'b', when: '2020-02-01T00:00:00.000Z');
    String? saved;
    final repo = FakeItemListsRepository(list: ItemList(entries: [a, b]));
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(),
      saveCsv: (csv) async {
        saved = csv;
        return '/tmp/item-list.csv';
      },
    );
    await controller.preview();
    controller.removeAt(0);
    expect(controller.entries.map((e) => e.itemId), ['b']);
    await controller.exportCsv();
    expect(saved, isNot(contains('photo,a,')));
    expect(saved, contains('photo,b,'));
  });

  test('preview passes the current filter to the server', () async {
    final repo = FakeItemListsRepository();
    final controller = ItemListExportController(
      repository: repo,
      itemsRepository: FakeItemsRepository(),
    );
    controller.toggleWhere('park');
    await controller.preview();
    expect(repo.lastFilter?.where, ['park']);
  });
}
