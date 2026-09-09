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
    return CapturedAtMutationResult.fromJson(
      _client.decodeMap(response, 'captured-at'),
    );
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
    return KeyPeriodMutationResult.fromJson(
      _client.decodeMap(response, 'key-period-bounds'),
    );
  }

  /// `POST /corrections/{correctionId}/undo` — restore prior approved value.
  ///
  /// Person-linking undos use S7/D9 native inverse ops, not this endpoint.
  Future<UndoCorrectionResult> undoCorrection(String correctionId) async {
    final response = await _client.post('/corrections/$correctionId/undo');
    return UndoCorrectionResult.fromJson(
      _client.decodeMap(response, 'undo-correction'),
    );
  }

  /// `POST /corrections/{correctionId}/redo` — re-apply original correction
  /// after undo when the entity is still in the undone state (S8 / R6).
  Future<RedoCorrectionResult> redoCorrection(String correctionId) async {
    final response = await _client.post('/corrections/$correctionId/redo');
    return RedoCorrectionResult.fromJson(
      _client.decodeMap(response, 'redo-correction'),
    );
  }

  TagMutationResult _tagMutation(http.Response response, String label) {
    return TagMutationResult.fromJson(_client.decodeMap(response, label));
  }
}
