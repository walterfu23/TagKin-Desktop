import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Typed client for owner-scoped `/items` (D2 Library & Item Registry).
///
/// Sends metadata/refs only — never media bytes (R1/R7). Owner is derived
/// server-side from the bearer token; this client never sends `ownerUserId`
/// (R10).
class ItemsRepository {
  ItemsRepository(this._client);

  final ApiClient _client;

  /// `GET /items` — optional [status] filter (server-side coarse filter).
  /// Optional [limit]/[offset] match the documented server cap (default 2000,
  /// max 5000). Client library table owns sort / text filter / pagination.
  Future<List<Item>> listItems({
    ProcessingStatus? status,
    int? limit,
    int? offset,
  }) async {
    final query = <String, String>{};
    if (status != null) query['status'] = status.wire;
    if (limit != null) query['limit'] = '$limit';
    if (offset != null) query['offset'] = '$offset';
    final response = await _client.get(
      '/items',
      query: query.isEmpty ? null : query,
    );
    return _client
        .decodeList(response, '/items')
        .map((e) => Item.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /items/{id}` — foreign ids surface as [ApiException] 404 (R10).
  Future<Item> getItem(String id) async {
    final response = await _client.get('/items/$id');
    return Item.fromJson(_client.decodeMap(response, '/items/{id}'));
  }

  /// `GET /items/{id}/knowledge` — approved who/what/when/where projection (D8).
  ///
  /// Metadata/text only — never media bytes (R1/R5). Owner is derived
  /// server-side from the bearer token; this client never sends `ownerUserId`
  /// (R10). Foreign ids surface as [ApiException] 404.
  Future<ItemKnowledge> getKnowledge(String itemId) async {
    final response = await _client.get('/items/$itemId/knowledge');
    return ItemKnowledge.fromJson(
      _client.decodeMap(response, '/items/{id}/knowledge'),
    );
  }

  /// `POST /items` — metadata/refs only ([CreateItem]); plumbing for D3.
  Future<Item> createItem(CreateItem input) async {
    final response = await _client.post('/items', body: input.toJson());
    return Item.fromJson(_client.decodeMap(response, 'create-item'));
  }

  /// `POST /items/{id}/pre-pass-result` — vectors/metadata/text only (D4).
  ///
  /// Never attaches media bytes (R1/R5). Owner is derived server-side from
  /// the bearer token; this client never sends `ownerUserId` (R10).
  Future<PrePassResultResponse> recordPrePassResult(
    String itemId,
    PrePassResult input,
  ) async {
    final response = await _client.post(
      '/items/$itemId/pre-pass-result',
      body: input.toJson(),
    );
    return PrePassResultResponse.fromJson(
      _client.decodeMap(response, 'pre-pass-result'),
    );
  }

  /// `POST /items/{id}/upload-grant` — mint a short-lived model-host URL (D5).
  ///
  /// Returns URL only — never a provider key (R8). Owner is derived
  /// server-side from the bearer token (R10).
  Future<UploadGrant> createUploadGrant(
    String itemId,
    CreateUploadGrant input,
  ) async {
    final response = await _client.post(
      '/items/$itemId/upload-grant',
      body: input.toJson(),
    );
    return UploadGrant.fromJson(_client.decodeMap(response, 'upload-grant'));
  }

  /// `POST /items/{id}/analysis-ref` — record model-host ref after direct
  /// upload (D5). Metadata/ref only — never media bytes (R1/R4).
  Future<Item> recordAnalysisRef(
    String itemId,
    RecordAnalysisRef input,
  ) async {
    final response = await _client.post(
      '/items/$itemId/analysis-ref',
      body: input.toJson(),
    );
    return Item.fromJson(_client.decodeMap(response, 'analysis-ref'));
  }

  /// `POST /items/{id}/link-people` — run server-side likeness matching (D9).
  ///
  /// Ingest still uses this after analyze. Item detail no longer exposes a
  /// button; humans assign via [assignPersonToItem] (R6).
  Future<LinkPeopleResponse> linkPeopleForItem(String itemId) async {
    final response = await _client.post('/items/$itemId/link-people');
    return LinkPeopleResponse.fromJson(
      _client.decodeMap(response, 'link-people'),
    );
  }

  /// `POST /items/{id}/assign-person` — assign a face crop (`tagId`) or, when
  /// the item has no crops, the whole item to an existing or new named person.
  Future<PersonAppearance> assignPersonToItem(
    String itemId, {
    String? personId,
    String? name,
    String? tagId,
  }) async {
    assert(
      personId != null || name != null,
      'assignPersonToItem requires personId or name',
    );
    final response = await _client.post(
      '/items/$itemId/assign-person',
      body: AssignPerson(
        personId: personId,
        name: name,
        tagId: tagId,
      ).toJson(),
    );
    return PersonAppearance.fromJson(
      _client.decodeMap(response, 'assign-person'),
    );
  }

  /// `POST /items/{id}/who-appearances` — face-crop embeddings for who tags,
  /// then server auto-runs suggested linking (R1/R6).
  Future<WhoAppearancesResponse> recordWhoAppearances(
    String itemId,
    WhoAppearancesRequest input,
  ) async {
    final response = await _client.post(
      '/items/$itemId/who-appearances',
      body: input.toJson(),
    );
    return WhoAppearancesResponse.fromJson(
      _client.decodeMap(response, 'who-appearances'),
    );
  }

  /// `POST /items/{id}/who-exclusions` — durable exclude face from this photo.
  Future<CreateWhoExclusionResult> createWhoExclusion(
    String itemId,
    String tagId,
  ) async {
    final response = await _client.post(
      '/items/$itemId/who-exclusions',
      body: CreateWhoExclusionRequest(tagId: tagId).toJson(),
    );
    return CreateWhoExclusionResult.fromJson(
      _client.decodeMap(response, 'who-exclusion'),
    );
  }

  /// `DELETE /items/{id}/who-exclusions/{exclusionId}` — undo exclude (R6).
  Future<WhoExclusion> undoWhoExclusion(
    String itemId,
    String exclusionId,
  ) async {
    final response = await _client.delete(
      '/items/$itemId/who-exclusions/$exclusionId',
    );
    final json = _client.decodeMap(response, 'undo who-exclusion');
    final exclusion = json['exclusion'];
    if (exclusion is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected undo who-exclusion response shape',
      );
    }
    return WhoExclusion.fromJson(exclusion);
  }

  /// `PATCH /items/{id}/source-ref` — sidecar retarget (metadata only, R1).
  Future<Item> retargetSourceRef(
    String itemId, {
    required String sourceRef,
    String? contentHash,
    String? perceptualHash,
  }) async {
    final response = await _client.patch(
      '/items/$itemId/source-ref',
      body: RetargetItemSourceRef(
        sourceRef: sourceRef,
        contentHash: contentHash,
        perceptualHash: perceptualHash,
      ).toJson(),
    );
    return Item.fromJson(_client.decodeMap(response, 'source-ref'));
  }
}
