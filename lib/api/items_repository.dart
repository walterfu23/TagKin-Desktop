import 'dart:convert';

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
  /// Client library table owns sort / text filter / pagination.
  Future<List<Item>> listItems({ProcessingStatus? status}) async {
    final response = await _client.get(
      '/items',
      query: status == null ? null : {'status': status.wire},
    );
    final json = jsonDecode(response.body);
    if (json is! List<dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /items response shape',
      );
    }
    return json
        .map((e) => Item.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /items/{id}` — foreign ids surface as [ApiException] 404 (R10).
  Future<Item> getItem(String id) async {
    final response = await _client.get('/items/$id');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /items/{id} response shape',
      );
    }
    return Item.fromJson(json);
  }

  /// `GET /items/{id}/knowledge` — approved who/what/when/where projection (D8).
  ///
  /// Metadata/text only — never media bytes (R1/R5). Owner is derived
  /// server-side from the bearer token; this client never sends `ownerUserId`
  /// (R10). Foreign ids surface as [ApiException] 404.
  Future<ItemKnowledge> getKnowledge(String itemId) async {
    final response = await _client.get('/items/$itemId/knowledge');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /items/{id}/knowledge response shape',
      );
    }
    return ItemKnowledge.fromJson(json);
  }

  /// `POST /items` — metadata/refs only ([CreateItem]); plumbing for D3.
  Future<Item> createItem(CreateItem input) async {
    final response = await _client.post('/items', body: input.toJson());
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected create-item response shape',
      );
    }
    return Item.fromJson(json);
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
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected pre-pass-result response shape',
      );
    }
    return PrePassResultResponse.fromJson(json);
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
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected upload-grant response shape',
      );
    }
    return UploadGrant.fromJson(json);
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
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected analysis-ref response shape',
      );
    }
    return Item.fromJson(json);
  }

  /// `POST /items/{id}/link-people` — run server-side likeness matching (D9).
  ///
  /// Ingest still uses this after analyze. Item detail no longer exposes a
  /// button; humans assign via [assignPersonToItem] (R6).
  Future<LinkPeopleResponse> linkPeopleForItem(String itemId) async {
    final response = await _client.post('/items/$itemId/link-people');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected link-people response shape',
      );
    }
    return LinkPeopleResponse.fromJson(json);
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
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected assign-person response shape',
      );
    }
    return PersonAppearance.fromJson(json);
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
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected who-appearances response shape',
      );
    }
    return WhoAppearancesResponse.fromJson(json);
  }

  /// `POST /items/{id}/who-exclusions` — durable exclude face from this photo.
  Future<CreateWhoExclusionResult> createWhoExclusion(
    String itemId,
    String tagId,
  ) async {
    final response = await _client.post(
      '/items/$itemId/who-exclusions',
      body: {'tagId': tagId},
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected who-exclusion response shape',
      );
    }
    return CreateWhoExclusionResult.fromJson(json);
  }

  /// `DELETE /items/{id}/who-exclusions/{exclusionId}` — undo exclude (R6).
  Future<WhoExclusion> undoWhoExclusion(
    String itemId,
    String exclusionId,
  ) async {
    final response = await _client.delete(
      '/items/$itemId/who-exclusions/$exclusionId',
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected undo who-exclusion response shape',
      );
    }
    final exclusion = json['exclusion'];
    if (exclusion is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected undo who-exclusion response shape',
      );
    }
    return WhoExclusion.fromJson(exclusion);
  }
}
