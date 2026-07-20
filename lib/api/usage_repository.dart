import 'dart:convert';

import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Typed client for owner-scoped `GET /usage` (D6 Cost & Usage Surface).
///
/// Read-only: displays server-authoritative usage/limit/kill-switch. Never
/// estimates cost client-side and never sends `ownerUserId` (R9/R10).
class UsageRepository {
  UsageRepository(this._client);

  final ApiClient _client;

  /// `GET /usage` — current usage, reservation, limits, and kill-switch.
  Future<UsageSummary> getUsage() async {
    final response = await _client.get('/usage');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /usage response shape',
      );
    }
    return UsageSummary.fromJson(json);
  }
}
