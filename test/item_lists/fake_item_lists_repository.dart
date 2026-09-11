import 'package:tagkin_desktop/api/item_lists_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

class FakeItemListsRepository implements ItemListsRepository {
  FakeItemListsRepository({
    this.facets = const ItemListFacets(who: [], what: [], where: []),
    this.list = const ItemList(entries: []),
    this.onCreate,
  });

  ItemListFacets facets;
  ItemList list;
  ItemListFilter? lastFilter;
  void Function(ItemListFilter filter)? onCreate;

  @override
  Future<ItemListFacets> listFacets() async => facets;

  @override
  Future<ItemList> createItemList(ItemListFilter filter) async {
    lastFilter = filter;
    onCreate?.call(filter);
    return list;
  }
}

ItemListEntry fixtureEntry({
  required String itemId,
  ItemListEntryKind kind = ItemListEntryKind.photo,
  String? keyPeriodId,
  int? startMs,
  int? endMs,
  String? when,
  List<String> who = const [],
  List<String> what = const [],
  List<String> where = const [],
}) {
  return ItemListEntry(
    kind: kind,
    itemId: itemId,
    keyPeriodId: keyPeriodId,
    startMs: startMs,
    endMs: endMs,
    when: when,
    who: who,
    what: what,
    where: where,
  );
}
