import 'dart:convert';

import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Typed client for person linking (D9).
///
/// Surfaces cross-item person suggestions and honor human confirm/correct.
/// Never sends media bytes or likeness vectors (R1); never sends
/// `ownerUserId` (R10); never implements similarity matching (R8/§4 — server).
class PersonsRepository {
  PersonsRepository(this._client);

  final ApiClient _client;

  /// `GET /persons` — optional [linkState] filter (owner-scoped, R10).
  Future<List<Person>> listPersons({LinkState? linkState}) async {
    final response = await _client.get(
      '/persons',
      query: linkState == null ? null : {'linkState': linkState.wire},
    );
    final json = jsonDecode(response.body);
    if (json is! List<dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /persons response shape',
      );
    }
    return json
        .map((e) => Person.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// `GET /persons/{id}` — foreign ids surface as [ApiException] 404 (R10).
  /// Never returns likeness vectors (R1).
  Future<PersonDetail> getPerson(String personId) async {
    final response = await _client.get('/persons/$personId');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected /persons/{id} response shape',
      );
    }
    return PersonDetail.fromJson(json);
  }

  /// `PATCH /persons/{id}` — rename a person (human-authored; R6).
  Future<Person> renamePerson(String personId, String? name) async {
    final response = await _client.patch(
      '/persons/$personId',
      body: RenamePerson(name: name).toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected rename-person response shape',
      );
    }
    return Person.fromJson(json);
  }

  /// `POST /persons/{id}/confirm` — move suggested → confirmed (R6).
  Future<PersonDetail> confirmPerson(String personId) async {
    final response = await _client.post('/persons/$personId/confirm');
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected confirm-person response shape',
      );
    }
    return PersonDetail.fromJson(json);
  }

  /// `POST /persons/{id}/split` — move appearances onto a new person (R6).
  Future<PersonDetail> splitPerson(
    String personId,
    List<String> appearanceIds,
  ) async {
    final response = await _client.post(
      '/persons/$personId/split',
      body: SplitPerson(appearanceIds: appearanceIds).toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected split-person response shape',
      );
    }
    return PersonDetail.fromJson(json);
  }

  /// `POST /persons/appearances/{id}/unlink` — clear personId (R6).
  Future<PersonAppearance> unlinkAppearance(String appearanceId) async {
    final response = await _client.post(
      '/persons/appearances/$appearanceId/unlink',
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected unlink-appearance response shape',
      );
    }
    return PersonAppearance.fromJson(json);
  }

  /// `POST /persons/appearances/{id}/reassign` — move to another person (R6).
  Future<PersonAppearance> reassignAppearance(
    String appearanceId,
    String personId,
  ) async {
    final response = await _client.post(
      '/persons/appearances/$appearanceId/reassign',
      body: ReassignAppearance(personId: personId).toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected reassign-appearance response shape',
      );
    }
    return PersonAppearance.fromJson(json);
  }
}
