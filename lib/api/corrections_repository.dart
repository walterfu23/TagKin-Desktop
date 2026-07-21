import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Typed client for knowledge corrections (D10 / S8).
///
/// Add/edit/remove tags, correct captured-at and key-period bounds, undo.
/// Metadata/text only — never media bytes (R1). Never sends `ownerUserId`
/// (R10). Server stamps `source=human`; client-supplied owner/source ignored.
class CorrectionsRepository {
  CorrectionsRepository(this._client);

  final ApiClient _client;

  /// `POST /items/{itemId}/tags` — human-add a tag (R6).
  Future<TagMutationResult> addTag(String itemId, AddTag input) async {
    final response = await _client.post(
      '/items/$itemId/tags',
      body: input.toJson(),
    );
    return _tagMutation(response, 'add-tag');
  }

  /// `PATCH /tags/{tagId}` — non-destructive edit (supersede; R6).
  Future<TagMutationResult> editTag(String tagId, EditTag input) async {
    final response = await _client.patch(
      '/tags/$tagId',
      body: input.toJson(),
    );
    return _tagMutation(response, 'edit-tag');
  }

  /// `DELETE /tags/{tagId}` — soft-remove (status=removed; R6).
  Future<TagMutationResult> removeTag(String tagId) async {
    final response = await _client.delete('/tags/$tagId');
    return _tagMutation(response, 'remove-tag');
  }

  /// `PATCH /items/{itemId}/captured-at` — correct when (R6).
  Future<CapturedAtMutationResult> correctCapturedAt(
    String itemId,
    CorrectCapturedAt input,
  ) async {
    final response = await _client.patch(
      '/items/$itemId/captured-at',
      body: input.toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected captured-at response shape',
      );
    }
    return CapturedAtMutationResult.fromJson(json);
  }

  /// `PATCH /key-periods/{keyPeriodId}` — correct start/end bounds (R6).
  Future<KeyPeriodMutationResult> correctKeyPeriodBounds(
    String keyPeriodId,
    CorrectKeyPeriodBounds input,
  ) async {
    final response = await _client.patch(
      '/key-periods/$keyPeriodId',
      body: input.toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected key-period-bounds response shape',
      );
    }
    return KeyPeriodMutationResult.fromJson(json);
  }

  /// `POST /corrections/{correctionId}/undo` — restore prior approved value.
  ///
  /// Person-linking undos use S7/D9 native inverse ops, not this endpoint.
  Future<UndoCorrectionResult> undoCorrection(String correctionId) async {
    final response = await _client.post('/corrections/$correctionId/undo');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected undo-correction response shape',
      );
    }
    return UndoCorrectionResult.fromJson(json);
  }

  TagMutationResult _tagMutation(http.Response response, String label) {
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected $label response shape',
      );
    }
    return TagMutationResult.fromJson(json);
  }
}
