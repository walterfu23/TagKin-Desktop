import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// In-memory [ItemsRepository] for widget/integration tests (no network).
class FakeItemsRepository implements ItemsRepository {
  FakeItemsRepository({
    List<Item>? items,
    this.getItemError,
    this.listError,
    this.grantFactory,
    this.grantError,
    this.analysisRefError,
  }) : _items = List<Item>.from(items ?? const []);

  final List<Item> _items;
  final Object? getItemError;
  final Object? listError;

  /// Optional grant factory; defaults to a non-expiring stub URL.
  final UploadGrant Function(String itemId, CreateUploadGrant input)?
      grantFactory;

  /// When set, [createUploadGrant] throws this (after optional first success
  /// via [grantSequence]).
  final Object? grantError;

  /// When set, [recordAnalysisRef] throws this.
  final Object? analysisRefError;

  /// Optional ordered grants (e.g. expired then fresh) consumed FIFO.
  final List<UploadGrant> grantSequence = <UploadGrant>[];

  final List<CreateItem> created = <CreateItem>[];
  final List<({String itemId, PrePassResult input})> prePassRecorded =
      <({String itemId, PrePassResult input})>[];
  final List<({String itemId, CreateUploadGrant input})> grantsMinted =
      <({String itemId, CreateUploadGrant input})>[];
  final List<({String itemId, RecordAnalysisRef input})> analysisRefRecorded =
      <({String itemId, RecordAnalysisRef input})>[];

  /// Removes an item from the in-memory library (D7 delete tests).
  void removeItem(String id) {
    _items.removeWhere((i) => i.id == id);
  }

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

  @override
  Future<UploadGrant> createUploadGrant(
    String itemId,
    CreateUploadGrant input,
  ) async {
    // Ensure the item exists (tenant-scoped).
    await getItem(itemId);
    grantsMinted.add((itemId: itemId, input: input));
    if (grantSequence.isNotEmpty) {
      return grantSequence.removeAt(0);
    }
    if (grantError != null) throw grantError!;
    if (grantFactory != null) {
      return grantFactory!(itemId, input);
    }
    return UploadGrant(
      uploadUrl:
          'https://stub.tagkin.test/upload?mime=${Uri.encodeComponent(input.mimeType)}',
      expiresAt: DateTime.now().add(const Duration(minutes: 15)).toIso8601String(),
    );
  }

  @override
  Future<Item> recordAnalysisRef(
    String itemId,
    RecordAnalysisRef input,
  ) async {
    if (analysisRefError != null) throw analysisRefError!;
    analysisRefRecorded.add((itemId: itemId, input: input));
    final index = _items.indexWhere((i) => i.id == itemId);
    if (index < 0) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    final prev = _items[index];
    final updated = Item(
      id: prev.id,
      type: prev.type,
      sourceType: prev.sourceType,
      sourceRef: prev.sourceRef,
      analysisRef: input.analysisRef,
      analysisRefState: AnalysisRefState.ready,
      contentHash: prev.contentHash,
      perceptualHash: prev.perceptualHash,
      dedupOfItemId: prev.dedupOfItemId,
      capturedAt: prev.capturedAt,
      processingStatus: ProcessingStatus.awaitingModelAccess,
      schemaVersion: prev.schemaVersion,
      createdAt: prev.createdAt,
    );
    _items[index] = updated;
    return updated;
  }
}

/// Fixture [Item] for tests.
Item fixtureItem({
  String id = 'item_1',
  ItemType type = ItemType.photo,
  ProcessingStatus processingStatus = ProcessingStatus.pending,
  String? capturedAt = '2026-07-01T12:00:00.000Z',
  AnalysisRefState analysisRefState = AnalysisRefState.pending,
  String? analysisRef,
}) {
  return Item(
    id: id,
    type: type,
    sourceType: SourceType.local,
    sourceRef: 'file:///tmp/$id.jpg',
    analysisRef: analysisRef,
    analysisRefState: analysisRefState,
    contentHash: 'hash_$id',
    capturedAt: capturedAt,
    processingStatus: processingStatus,
    schemaVersion: 1,
    createdAt: '2026-07-19T00:00:00.000Z',
  );
}
