import 'dart:convert';

import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Typed client for tagging + jobs lifecycle (D7).
///
/// Triggers analysis, lists jobs, cancel, delete, and library export. Never
/// sends media bytes (R1/R5/R7) or `ownerUserId` (R10). Never estimates cost
/// or routes providers (R8/R9 — server-authoritative).
class JobsRepository {
  JobsRepository(this._client);

  final ApiClient _client;

  /// `POST /items/{id}/analyze` — image-only tagging (photo items; R9).
  ///
  /// A `409` BudgetExceeded surfaces as [ApiException] with the server
  /// message; callers must not auto-retry around it.
  Future<AnalyzeResultResponse> analyzeItem(String itemId) async {
    final response = await _client.post('/items/$itemId/analyze');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected analyze response shape',
      );
    }
    return AnalyzeResultResponse.fromJson(json);
  }

  /// `GET /items/{id}/jobs` — most-recent-first durable jobs for the item.
  Future<List<Job>> listItemJobs(String itemId) async {
    final response = await _client.get('/items/$itemId/jobs');
    final json = jsonDecode(response.body);
    if (json is! List<dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /jobs response shape',
      );
    }
    return json
        .map((e) => Job.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `POST /items/{id}/cancel` — stop unfinished work; release reservation.
  Future<CancelItemResponse> cancelItem(String itemId) async {
    final response = await _client.post('/items/$itemId/cancel');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected cancel response shape',
      );
    }
    return CancelItemResponse.fromJson(json);
  }

  /// `DELETE /items/{id}` — soft-delete TagKin metadata; never touches local
  /// media (R1/R5/R10). Expects `204`.
  Future<void> deleteItem(String itemId) async {
    await _client.delete('/items/$itemId');
  }

  /// `GET /export` — owner-scoped library knowledge only (no media bytes).
  Future<LibraryExport> exportLibrary() async {
    final response = await _client.get('/export');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /export response shape',
      );
    }
    return LibraryExport.fromJson(json);
  }
}
