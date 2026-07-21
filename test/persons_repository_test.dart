import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

Map<String, dynamic> _personJson({
  required String id,
  String? name = 'Sam',
  String linkState = 'suggested',
}) =>
    {
      'id': id,
      'name': name,
      'linkState': linkState,
      'createdAt': '2026-07-20T00:00:00.000Z',
    };

Map<String, dynamic> _appearanceJson({
  required String id,
  String? personId = 'person_1',
  String? itemId = 'item_1',
  String linkState = 'suggested',
}) =>
    {
      'id': id,
      'personId': personId,
      'itemId': itemId,
      'keyPeriodId': null,
      'linkState': linkState,
      'createdAt': '2026-07-20T00:00:00.000Z',
    };

Map<String, dynamic> _personDetailJson({
  required String id,
  String? name = 'Sam',
  String linkState = 'suggested',
}) =>
    {
      ..._personJson(id: id, name: name, linkState: linkState),
      'appearances': [
        _appearanceJson(id: 'ap_1', personId: id, linkState: linkState),
      ],
    };

void main() {
  group('PersonsRepository', () {
    test('listPersons returns owner-scoped persons from GET /persons',
        () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/persons');
        expect(request.headers['Authorization'], 'Bearer tok-a');
        return http.Response(
          jsonEncode([
            _personJson(id: 'person_a1'),
            _personJson(id: 'person_a2', linkState: 'confirmed'),
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok-a',
        httpClient: mock,
      );
      final persons = await PersonsRepository(client).listPersons();
      expect(persons.map((p) => p.id), ['person_a1', 'person_a2']);
      expect(persons[1].linkState, LinkState.confirmed);
      client.close();
    });

    test('listPersons passes optional linkState query', () async {
      final mock = MockClient((request) async {
        expect(request.url.queryParameters['linkState'], 'suggested');
        return http.Response(jsonEncode([]), 200);
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      await PersonsRepository(client)
          .listPersons(linkState: LinkState.suggested);
      client.close();
    });

    test('getPerson returns detail; foreign id surfaces 404 (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/persons/foreign');
        return http.Response(
          jsonEncode({'code': 'not_found', 'message': 'Not found'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok-a',
        httpClient: mock,
      );
      await expectLater(
        PersonsRepository(client).getPerson('foreign'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      client.close();
    });

    test('getPerson response never includes embedding vector (R1)', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode(_personDetailJson(id: 'person_1')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final detail = await PersonsRepository(client).getPerson('person_1');
      final json = detail.toJson();
      expect(json.containsKey('embedding'), isFalse);
      expect(json.containsKey('vector'), isFalse);
      for (final a in detail.appearances) {
        expect(a.toJson().containsKey('embedding'), isFalse);
      }
      client.close();
    });

    test('confirmPerson posts to /persons/{id}/confirm', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/persons/person_1/confirm');
        expect(request.body.isEmpty || request.body == 'null', isTrue);
        return http.Response(
          jsonEncode(_personDetailJson(id: 'person_1', linkState: 'confirmed')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;
      final detail =
          await PersonsRepository(client).confirmPerson('person_1');
      expect(detail.linkState, LinkState.confirmed);
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });

    test('splitPerson posts appearanceIds only — no owner (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/persons/person_1/split');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'appearanceIds'});
        expect(body['appearanceIds'], ['ap_1']);
        expect(body.containsKey('ownerUserId'), isFalse);
        return http.Response(
          jsonEncode(_personDetailJson(id: 'person_new')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;
      final created = await PersonsRepository(client).splitPerson(
        'person_1',
        ['ap_1'],
      );
      expect(created.id, 'person_new');
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });

    test('unlinkAppearance posts to appearances/{id}/unlink', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/persons/appearances/ap_1/unlink');
        return http.Response(
          jsonEncode(_appearanceJson(id: 'ap_1', personId: null)),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final appearance =
          await PersonsRepository(client).unlinkAppearance('ap_1');
      expect(appearance.personId, isNull);
      client.close();
    });

    test('reassignAppearance posts personId only — no owner (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/persons/appearances/ap_1/reassign');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'personId'});
        expect(body['personId'], 'person_2');
        expect(body.containsKey('ownerUserId'), isFalse);
        return http.Response(
          jsonEncode(
            _appearanceJson(
              id: 'ap_1',
              personId: 'person_2',
              linkState: 'confirmed',
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;
      final appearance = await PersonsRepository(client).reassignAppearance(
        'ap_1',
        'person_2',
      );
      expect(appearance.personId, 'person_2');
      expect(appearance.linkState, LinkState.confirmed);
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });

    test('renamePerson patches name — no owner (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/persons/person_1');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'name'});
        expect(body['name'], 'Alex');
        expect(body.containsKey('ownerUserId'), isFalse);
        return http.Response(
          jsonEncode(_personJson(id: 'person_1', name: 'Alex')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;
      final person =
          await PersonsRepository(client).renamePerson('person_1', 'Alex');
      expect(person.name, 'Alex');
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });
  });

  group('ItemsRepository.linkPeopleForItem', () {
    test('posts to /items/{id}/link-people with empty body (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items/item_1/link-people');
        expect(request.body.isEmpty || request.body == 'null', isTrue);
        return http.Response(
          jsonEncode({
            'appearances': [
              _appearanceJson(id: 'ap_1', personId: 'person_1'),
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;
      final result =
          await ItemsRepository(client).linkPeopleForItem('item_1');
      expect(result.appearances.single.id, 'ap_1');
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });
  });
}
