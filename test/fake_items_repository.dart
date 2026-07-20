import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// In-memory [ItemsRepository] for widget/integration tests (no network).
class FakeItemsRepository implements ItemsRepository {
  FakeItemsRepository({
    List<Item>? items,
    this.getItemError,
    this.listError,
  }) : _items = List<Item>.from(items ?? const []);

  final List<Item> _items;
  final Object? getItemError;
  final Object? listError;

  final List<CreateItem> created = <CreateItem>[];
  final List<({String itemId, PrePassResult input})> prePassRecorded =
      <({String itemId, PrePassResult input})>[];

  @override
  Future<List<Item>> listItems({ProcessingStatus? status}) async {
    if (listError != null) throw listError!;
    if (status == null) return List<Item>.from(_items);
    return _items.where((i) => i.processingStatus == status).toList();
  }

  @override
  Future<Item> getItem(String id) async {
    if (getItemError != null) throw getItemError!;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  @override
  Future<Item> createItem(CreateItem input) async {
    created.add(input);
    final item = Item(
      id: 'item_${_items.length + 1}',
      type: input.type,
      sourceType: input.sourceType,
      sourceRef: input.sourceRef,
      analysisRef: null,
      analysisRefState: AnalysisRefState.pending,
      contentHash: input.contentHash,
      capturedAt: input.capturedAt,
      processingStatus: ProcessingStatus.pending,
      schemaVersion: 1,
      createdAt: '2026-07-19T00:00:00.000Z',
    );
    _items.add(item);
    return item;
  }

  @override
  Future<PrePassResultResponse> recordPrePassResult(
    String itemId,
    PrePassResult input,
  ) async {
    prePassRecorded.add((itemId: itemId, input: input));
    final item = await getItem(itemId);
    return PrePassResultResponse(
      item: item,
      keyPeriodIds: const [],
      appearanceIds: const [],
      tagIds: const [],
    );
  }
}

/// Fixture [Item] for tests.
Item fixtureItem({
  String id = 'item_1',
  ItemType type = ItemType.photo,
  ProcessingStatus processingStatus = ProcessingStatus.pending,
  String? capturedAt = '2026-07-01T12:00:00.000Z',
}) {
  return Item(
    id: id,
    type: type,
    sourceType: SourceType.local,
    sourceRef: 'file:///tmp/$id.jpg',
    analysisRef: null,
    analysisRefState: AnalysisRefState.pending,
    contentHash: 'hash_$id',
    capturedAt: capturedAt,
    processingStatus: processingStatus,
    schemaVersion: 1,
    createdAt: '2026-07-19T00:00:00.000Z',
  );
}
