import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

import 'fake_persons_repository.dart';

/// In-memory [ItemsRepository] for widget/integration tests (no network).
class FakeItemsRepository implements ItemsRepository {
  FakeItemsRepository({
    List<Item>? items,
    Map<String, ItemKnowledge>? knowledgeByItemId,
    this.getItemError,
    this.listError,
    this.getKnowledgeError,
    this.grantFactory,
    this.grantError,
    this.analysisRefError,
    this.onListItems,
    this.linkedPersons,
  })  : _items = List<Item>.from(items ?? const []),
        _knowledgeByItemId = Map<String, ItemKnowledge>.from(
          knowledgeByItemId ?? const {},
        );

  final List<Item> _items;
  final Map<String, ItemKnowledge> _knowledgeByItemId;
  final Object? getItemError;
  final Object? listError;
  final Object? getKnowledgeError;

  /// Optional hook before returning the list (e.g. inject one-shot failures).
  final Future<void> Function()? onListItems;

  /// When set, [createWhoExclusion] / [undoWhoExclusion] also mutate the
  /// linked persons fake (copy faceGroupId, move appearances ↔ exclusions).
  FakePersonsRepository? linkedPersons;

  /// Monotonic suffix so each [createWhoExclusion] remints a unique id
  /// (matches real API; catches stale undoWhoExclusion after redo).
  int _whoExclusionSeq = 0;

  final List<({String itemId, String tagId})> createWhoExclusionCalls =
      <({String itemId, String tagId})>[];
  final List<({String itemId, String exclusionId})> undoWhoExclusionCalls =
      <({String itemId, String exclusionId})>[];
  final Map<String, Tag> _excludedWhoTagsByTagId = {};

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

  /// Call log for [getItem] — tests use this to assert callers threading an
  /// already-known [Item] skip the network round trip (D9 Faces perf).
  final List<String> getItemCalls = <String>[];

  final List<CreateItem> created = <CreateItem>[];
  final List<({String itemId, PrePassResult input})> prePassRecorded =
      <({String itemId, PrePassResult input})>[];
  final List<({String itemId, CreateUploadGrant input})> grantsMinted =
      <({String itemId, CreateUploadGrant input})>[];
  final List<({String itemId, RecordAnalysisRef input})> analysisRefRecorded =
      <({String itemId, RecordAnalysisRef input})>[];

  /// Appearances returned by [linkPeopleForItem] (D9 tests).
  final List<PersonAppearance> linkPeopleResult = <PersonAppearance>[];

  /// Call log for [linkPeopleForItem].
  final List<String> linkPeopleCalls = <String>[];

  /// When set, [linkPeopleForItem] throws this.
  Object? linkPeopleError;

  /// Removes an item from the in-memory library (D7 delete tests).
  void removeItem(String id) {
    _items.removeWhere((i) => i.id == id);
  }

  /// In-memory item by id (no network). Used by [FakeJobsRepository] so batch
  /// analyze keeps sourceRef / type from the library row.
  Item? peekItem(String id) {
    for (final item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Replaces a stored item by id (D7 analyze/retry then library reload).
  void replaceItem(Item item) {
    final index = _items.indexWhere((i) => i.id == item.id);
    if (index < 0) {
      _items.add(item);
      return;
    }
    _items[index] = item;
  }

  /// Test helper: append an item for reload scenarios (e.g. new sibling folder).
  void addItem(Item item) {
    _items.add(item);
  }

  /// Updates the stored knowledge projection (D10 correction fakes).
  void setKnowledge(String itemId, ItemKnowledge knowledge) {
    _knowledgeByItemId[itemId] = knowledge;
  }

  /// Returns stored knowledge without falling back (D10 fakes).
  ItemKnowledge? peekKnowledge(String itemId) => _knowledgeByItemId[itemId];

  @override
  Future<List<Item>> listItems({ProcessingStatus? status}) async {
    if (onListItems != null) await onListItems!();
    if (listError != null) throw listError!;
    if (status == null) return List<Item>.from(_items);
    return _items.where((i) => i.processingStatus == status).toList();
  }

  @override
  Future<Item> getItem(String id) async {
    getItemCalls.add(id);
    if (getItemError != null) throw getItemError!;
    for (final item in _items) {
      if (item.id == id) return item;
    }
    throw ApiException(statusCode: 404, message: 'Not found');
  }

  @override
  Future<ItemKnowledge> getKnowledge(String itemId) async {
    if (getKnowledgeError != null) throw getKnowledgeError!;
    final knowledge = _knowledgeByItemId[itemId];
    if (knowledge != null) return knowledge;
    // Fall back to empty projection for items that exist in the library.
    final item = await getItem(itemId);
    return ItemKnowledge(
      item: item,
      tags: const [],
      keyPeriods: const [],
      appearances: const [],
      corrections: const [],
      whoExclusions: const [],
    );
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

  @override
  Future<LinkPeopleResponse> linkPeopleForItem(String itemId) async {
    await getItem(itemId);
    linkPeopleCalls.add(itemId);
    if (linkPeopleError != null) throw linkPeopleError!;
    // Merge linked appearances into stored knowledge when present.
    final existing = _knowledgeByItemId[itemId];
    if (existing != null && linkPeopleResult.isNotEmpty) {
      _knowledgeByItemId[itemId] = ItemKnowledge(
        item: existing.item,
        tags: existing.tags,
        keyPeriods: existing.keyPeriods,
        appearances: linkPeopleResult,
        corrections: existing.corrections,
        whoExclusions: existing.whoExclusions,
      );
    }
    return LinkPeopleResponse(appearances: List.from(linkPeopleResult));
  }

  final List<({String itemId, String? personId, String? name, String? tagId})>
      assignPersonCalls =
      <({String itemId, String? personId, String? name, String? tagId})>[];

  Object? assignPersonError;

  @override
  Future<PersonAppearance> assignPersonToItem(
    String itemId, {
    String? personId,
    String? name,
    String? tagId,
  }) async {
    await getItem(itemId);
    assignPersonCalls.add(
      (itemId: itemId, personId: personId, name: name, tagId: tagId),
    );
    if (assignPersonError != null) throw assignPersonError!;
    final existing = _knowledgeByItemId[itemId];
    if (tagId == null && existing != null) {
      final hasCrop = existing.tags.any(
        (t) =>
            t.dimension == 'who' &&
            t.status == TagStatus.active &&
            t.region != null,
      );
      if (hasCrop) {
        throw ApiException(
          statusCode: 409,
          message: 'item_has_face_crops',
        );
      }
    }
    var pid = personId;
    if (pid == null) {
      final n = name ?? 'Person';
      pid = 'person_${n.toLowerCase().replaceAll(' ', '_')}';
      final linked = linkedPersons;
      if (linked != null &&
          !linked.personDetails.any((p) => p.id == pid)) {
        linked.personDetails.add(
          fixturePersonDetail(id: pid, name: n, appearances: const []),
        );
      }
    }
    final appearance = PersonAppearance(
      id: 'ap_assign_${tagId ?? itemId}_$pid',
      personId: pid,
      itemId: itemId,
      tagId: tagId,
      assignmentState: 'confirmed',
      createdAt: '2026-08-13T00:00:00.000Z',
    );
    if (existing != null) {
      final next = [
        for (final a in existing.appearances)
          if (tagId == null
              ? a.personId != pid || a.tagId != null
              : a.tagId != tagId)
            a,
        appearance,
      ];
      _knowledgeByItemId[itemId] = ItemKnowledge(
        item: existing.item,
        tags: existing.tags,
        keyPeriods: existing.keyPeriods,
        appearances: next,
        corrections: existing.corrections,
        whoExclusions: existing.whoExclusions,
      );
    }
    return appearance;
  }

  final List<WhoAppearancesRequest> whoAppearancesRecorded =
      <WhoAppearancesRequest>[];

  @override
  Future<WhoAppearancesResponse> recordWhoAppearances(
    String itemId,
    WhoAppearancesRequest input,
  ) async {
    await getItem(itemId);
    whoAppearancesRecorded.add(input);
    final appearances = input.appearances
        .map(
          (a) => PersonAppearance(
            id: 'app_${a.tagId}',
            personId: 'person_auto',
            itemId: itemId,
            tagId: a.tagId,
            createdAt: '2026-07-25T00:00:00.000Z',
          ),
        )
        .toList();
    return WhoAppearancesResponse(
      appearanceIds: appearances.map((a) => a.id).toList(),
      appearances: appearances,
    );
  }

  @override
  Future<CreateWhoExclusionResult> createWhoExclusion(
    String itemId,
    String tagId,
  ) async {
    await getItem(itemId);
    createWhoExclusionCalls.add((itemId: itemId, tagId: tagId));

    String? faceGroupId;
    FaceGroupKind? faceGroupKind;
    TagRegion region =
        const TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.5, xMax: 0.5);

    final persons = linkedPersons;
    if (persons != null) {
      PersonAppearance? found;
      found = persons.takeAppearanceByTagId(tagId);
      if (found != null) {
        faceGroupId = found.faceGroupId;
        faceGroupKind = found.faceGroupKind;
        if (found.region != null) region = found.region!;
      }
    }

    final exclusion = WhoExclusion(
      id: 'excl_${tagId}_${++_whoExclusionSeq}',
      itemId: itemId,
      region: region,
      createdFromTagId: tagId,
      createdAt: '2026-07-26T00:00:00.000Z',
      faceGroupId: faceGroupId,
      faceGroupKind: faceGroupKind,
    );
    persons?.accountExclusions.add(exclusion);

    final existing = _knowledgeByItemId[itemId];
    if (existing != null) {
      for (final tag in existing.tags) {
        if (tag.id == tagId) {
          _excludedWhoTagsByTagId[tagId] = tag;
          break;
        }
      }
      _knowledgeByItemId[itemId] = ItemKnowledge(
        item: existing.item,
        tags: existing.tags.where((t) => t.id != tagId).toList(),
        keyPeriods: existing.keyPeriods,
        appearances:
            existing.appearances.where((a) => a.tagId != tagId).toList(),
        corrections: existing.corrections,
        whoExclusions: [...existing.whoExclusions, exclusion],
      );
    }
    return CreateWhoExclusionResult(
      exclusion: exclusion,
      removedTagId: tagId,
    );
  }

  @override
  Future<WhoExclusion> undoWhoExclusion(
    String itemId,
    String exclusionId,
  ) async {
    await getItem(itemId);
    undoWhoExclusionCalls.add((itemId: itemId, exclusionId: exclusionId));
    final existing = _knowledgeByItemId[itemId];
    WhoExclusion? found;
    if (existing != null) {
      for (final e in existing.whoExclusions) {
        if (e.id == exclusionId) found = e;
      }
      Tag? restoredTag;
      final tagId = found?.createdFromTagId;
      if (tagId != null) {
        restoredTag = _excludedWhoTagsByTagId.remove(tagId);
        restoredTag ??= Tag(
          id: tagId,
          itemId: itemId,
          dimension: 'who',
          value: 'face',
          source: KnowledgeSource.model,
          status: TagStatus.active,
          region: found!.region,
          schemaVersion: 1,
          createdAt: found.createdAt,
        );
      }
      final alreadyHasTag = restoredTag != null &&
          existing.tags.any((t) => t.id == restoredTag!.id);
      _knowledgeByItemId[itemId] = ItemKnowledge(
        item: existing.item,
        tags: [
          ...existing.tags,
          if (restoredTag != null && !alreadyHasTag) restoredTag,
        ],
        keyPeriods: existing.keyPeriods,
        appearances: existing.appearances,
        corrections: existing.corrections,
        whoExclusions:
            existing.whoExclusions.where((e) => e.id != exclusionId).toList(),
      );
    }

    final persons = linkedPersons;
    if (persons != null) {
      final idx =
          persons.accountExclusions.indexWhere((e) => e.id == exclusionId);
      if (idx >= 0) {
        found ??= persons.accountExclusions[idx];
        persons.accountExclusions.removeAt(idx);
      }
      if (found != null) {
        persons.unassignedAppearances.add(
          PersonAppearance(
            id: 'ap_restored_${found.id}',
            personId: null,
            faceGroupId: found.faceGroupId,
            faceGroupKind: found.faceGroupKind,
            itemId: found.itemId,
            tagId: found.createdFromTagId,
            region: found.region,
            createdAt: found.createdAt,
          ),
        );
      }
    }

    if (found == null) {
      throw ApiException(statusCode: 404, message: 'Not found');
    }
    return found;
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
  String? sourceRef,
  String? contentHash = '__default__',
}) {
  return Item(
    id: id,
    type: type,
    sourceType: SourceType.local,
    sourceRef: sourceRef ?? 'file:///fixture_$id/$id.jpg',
    analysisRef: analysisRef,
    analysisRefState: analysisRefState,
    contentHash: contentHash == '__default__' ? 'hash_$id' : contentHash,
    capturedAt: capturedAt,
    processingStatus: processingStatus,
    schemaVersion: 1,
    createdAt: '2026-07-19T00:00:00.000Z',
  );
}

/// Fixture [Tag] for D8 knowledge tests.
Tag fixtureTag({
  String id = 'tag_1',
  String? itemId = 'item_1',
  String? keyPeriodId,
  String dimension = 'what',
  String value = 'picnic',
  KnowledgeSource source = KnowledgeSource.model,
  TagStatus status = TagStatus.active,
  double? confidence = 0.9,
  String? provider = 'stub',
  String? modelId = 'stub-model',
  TagRegion? region,
}) {
  return Tag(
    id: id,
    itemId: itemId,
    keyPeriodId: keyPeriodId,
    dimension: dimension,
    value: value,
    source: source,
    status: status,
    confidence: confidence,
    provider: provider,
    modelId: modelId,
    region: region,
    schemaVersion: 1,
    createdAt: '2026-07-19T00:00:00.000Z',
  );
}

/// Fixture [ItemKnowledge] for D8 review tests.
ItemKnowledge fixtureKnowledge({
  Item? item,
  List<Tag>? tags,
  List<KeyPeriodKnowledge>? keyPeriods,
  List<PersonAppearance>? appearances,
  List<Correction>? corrections,
  List<WhoExclusion>? whoExclusions,
}) {
  final resolved = item ?? fixtureItem(processingStatus: ProcessingStatus.tagged);
  return ItemKnowledge(
    item: resolved,
    tags: tags ??
        [
          fixtureTag(id: 'tag_who', dimension: 'who', value: 'Sam'),
          fixtureTag(id: 'tag_what', dimension: 'what', value: 'picnic'),
          fixtureTag(id: 'tag_when', dimension: 'when', value: '2026-07-01'),
          fixtureTag(id: 'tag_where', dimension: 'where', value: 'park'),
        ],
    keyPeriods: keyPeriods ?? const [],
    appearances: appearances ?? const [],
    corrections: corrections ?? const [],
    whoExclusions: whoExclusions ?? const [],
  );
}
