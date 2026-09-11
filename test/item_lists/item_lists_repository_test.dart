import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/item_lists_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

void main() {
  group('ItemListsRepository', () {
    test('createItemList POSTs filter and never sends ownerUserId (R10)',
        () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/item-lists');
        expect(request.headers['Authorization'], 'Bearer tok-a');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('ownerUserId'), isFalse);
        expect(body.containsKey('accountId'), isFalse);
        expect(body['who'], ['Sam']);
        return http.Response(
          jsonEncode({
            'entries': [
              {
                'kind': 'photo',
                'itemId': '11111111-1111-1111-1111-111111111111',
                'keyPeriodId': null,
                'startMs': null,
                'endMs': null,
                'when': '2020-01-01T00:00:00.000Z',
                'who': ['Sam'],
                'what': <String>[],
                'where': <String>[],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok-a',
        httpClient: mock,
      )..recordRequests = true;

      final list = await ItemListsRepository(client).createItemList(
        const ItemListFilter(who: ['Sam']),
      );
      expect(list.entries, hasLength(1));
      expect(list.entries.single.kind, ItemListEntryKind.photo);
      expect(list.entries.single.who, ['Sam']);
      expect(
        client.recordedRequests.single.bodyContainsOwnerField,
        isFalse,
      );
      client.close();
    });

    test('listFacets GETs /item-lists/facets with no body (R1)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/item-lists/facets');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'who': ['Sam'],
            'what': ['swimming'],
            'where': ['park'],
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
      final facets = await ItemListsRepository(client).listFacets();
      expect(facets.who, ['Sam']);
      expect(client.recordedRequests.single.body, isNull);
      client.close();
    });

    test('foreign/unauthorized surfaces ApiException (R10)', () async {
      final mock = MockClient((request) async {
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
        ItemListsRepository(client).createItemList(const ItemListFilter()),
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 404)),
      );
      client.close();
    });
  });
}
