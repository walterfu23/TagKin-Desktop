import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Fetches the authenticated [Account] via `GET /me`.
///
/// Owner is derived server-side from the bearer token — this client never
/// sends `ownerUserId` (R10).
class MeRepository {
  MeRepository(this._client);

  final ApiClient _client;

  /// Resolves the current account. Throws [UnauthorizedException] on 401.
  Future<Account> getMe() async {
    final response = await _client.get('/me');
    return Account.fromJson(_client.decodeMap(response, '/me'));
  }
}
