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

  /// `GET /persons` — owner-scoped (R10).
  Future<List<Person>> listPersons() async {
    final response = await _client.get('/persons');
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

  /// `PATCH /persons/{id}` — rename a person (human-authored; R6). Name must
  /// be a non-empty string (Person.name is always required, R2).
  Future<Person> renamePerson(String personId, String name) async {
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

  /// `POST /persons/appearances/{id}/unlink` — clear personId / faceGroupId,
  /// back to loose Unassigned (R6).
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
  /// Pass an existing [personId], or [name] to create a new named person then
  /// assign. Exactly one of [personId] / [name] is required.
  Future<PersonAppearance> reassignAppearance(
    String appearanceId, {
    String? personId,
    String? name,
  }) async {
    assert(
      personId != null || name != null,
      'reassignAppearance requires personId or name',
    );
    final response = await _client.post(
      '/persons/appearances/$appearanceId/reassign',
      body: ReassignAppearance(personId: personId, name: name).toJson(),
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

  /// `POST /persons/face-groups/{id}/assign` — promote a GroupFA/GroupFM into
  /// a named Person (GroupP when ≥2 faces). Prior FaceGroup is deleted (R6).
  /// Exactly one of [personId] / [name] is required.
  Future<PersonDetail> assignFaceGroup(
    String faceGroupId, {
    String? personId,
    String? name,
  }) async {
    assert(
      personId != null || name != null,
      'assignFaceGroup requires personId or name',
    );
    final response = await _client.post(
      '/persons/face-groups/$faceGroupId/assign',
      body: AssignFaceGroup(personId: personId, name: name).toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected assign-face-group response shape',
      );
    }
    return PersonDetail.fromJson(json);
  }

  /// `POST /persons/appearances/unassign` — move appearances to Unassigned.
  /// Two or more become GroupFM; a single face becomes loose (R6).
  Future<List<PersonAppearance>> unassignAppearances(
    List<String> appearanceIds,
  ) async {
    final response = await _client.post(
      '/persons/appearances/unassign',
      body: UnassignAppearances(appearanceIds: appearanceIds).toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected unassign-appearances response shape',
      );
    }
    return UnassignAppearancesResponse.fromJson(json).appearances;
  }

  /// `POST /persons/appearances/assemble` — ≥2 loose faces → one GroupFM.
  Future<AssembleAppearancesResponse> assembleAppearances(
    List<String> appearanceIds,
  ) async {
    final response = await _client.post(
      '/persons/appearances/assemble',
      body: AssembleAppearances(appearanceIds: appearanceIds).toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected assemble-appearances response shape',
      );
    }
    return AssembleAppearancesResponse.fromJson(json);
  }

  /// `POST /persons/exclusions/assemble` — ≥2 loose exclusions → one GroupFM.
  Future<AssembleExclusionsResponse> assembleExclusions(
    List<String> exclusionIds,
  ) async {
    final response = await _client.post(
      '/persons/exclusions/assemble',
      body: AssembleExclusions(exclusionIds: exclusionIds).toJson(),
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected assemble-exclusions response shape',
      );
    }
    return AssembleExclusionsResponse.fromJson(json);
  }

  /// `POST /persons/face-groups/{id}/ungroup` — dissolve GroupFM → loose faces.
  Future<UngroupFaceGroupResponse> ungroupFaceGroup(String faceGroupId) async {
    final response = await _client.post(
      '/persons/face-groups/$faceGroupId/ungroup',
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected ungroup-face-group response shape',
      );
    }
    return UngroupFaceGroupResponse.fromJson(json);
  }

  /// `GET /persons/appearances/unassigned` — Unassigned tray (R1: no embeddings).
  Future<UnassignedAppearancesPage> listUnassignedAppearances({
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _client.get(
      '/persons/appearances/unassigned',
      query: {
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected unassigned-appearances response shape',
      );
    }
    return UnassignedAppearancesPage.fromJson(json);
  }

  /// `GET /persons/appearances/assigned` — Assigned tray overview (R1: no embeddings).
  Future<AssignedAppearancesPage> listAssignedAppearances({
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _client.get(
      '/persons/appearances/assigned',
      query: {
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected assigned-appearances response shape',
      );
    }
    return AssignedAppearancesPage.fromJson(json);
  }

  /// `GET /persons/exclusions` — Excluded tray across all items.
  Future<AccountWhoExclusionsPage> listAccountWhoExclusions({
    int limit = 100,
    int offset = 0,
  }) async {
    final response = await _client.get(
      '/persons/exclusions',
      query: {
        'limit': '$limit',
        'offset': '$offset',
      },
    );
    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw ApiException(
        statusCode: response.statusCode,
        message: 'Unexpected account-exclusions response shape',
      );
    }
    return AccountWhoExclusionsPage.fromJson(json);
  }

  /// `DELETE /persons/{id}` — dissolve person; appearances become unassigned (R6).
  Future<void> deletePerson(String personId) async {
    await _client.delete('/persons/$personId');
  }
}
