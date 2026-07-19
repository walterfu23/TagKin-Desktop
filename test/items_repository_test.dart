import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

Map<String, dynamic> _itemJson({
  required String id,
  String type = 'photo',
  String status = 'pending',
}) =>
    {
      'id': id,
      'type': type,
      'sourceType': 'local',
      'sourceRef': 'file:///tmp/$id.jpg',
      'analysisRef': null,
      'analysisRefState': 'pending',
      'contentHash': 'hash_$id',
      'perceptualHash': null,
      'dedupOfItemId': null,
      'capturedAt': '2026-07-01T12:00:00.000Z',
      'processingStatus': status,
      'schemaVersion': 1,
      'createdAt': '2026-07-19T00:00:00.000Z',
    };

void main() {
  group('ItemsRepository', () {
    test('listItems returns owner-scoped items from GET /items', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/items');
        expect(request.headers['Authorization'], 'Bearer tok-a');
        return http.Response(
          jsonEncode([
            _itemJson(id: 'item_a1'),
            _itemJson(id: 'item_a2', type: 'video', status: 'tagged'),
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
      final items = await ItemsRepository(client).listItems();
      expect(items.map((i) => i.id), ['item_a1', 'item_a2']);
      expect(items[1].processingStatus, ProcessingStatus.tagged);
      client.close();
    });

    test('listItems passes optional status query', () async {
      final mock = MockClient((request) async {
        expect(request.url.queryParameters['status'], 'tagged');
        return http.Response(jsonEncode([]), 200);
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      await ItemsRepository(client).listItems(status: ProcessingStatus.tagged);
      client.close();
    });

    test('getItem returns item; foreign id surfaces 404 (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/items/foreign');
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
        ItemsRepository(client).getItem('foreign'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      client.close();
    });

    test('createItem sends metadata/refs only — no byte/blob fields (R1)',
        () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items');
        expect(request.headers['Content-Type'], 'application/json');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {
          'type',
          'sourceType',
          'sourceRef',
          'contentHash',
          'capturedAt',
        });
        expect(body.containsKey('bytes'), isFalse);
        expect(body.containsKey('blob'), isFalse);
        expect(body.containsKey('data'), isFalse);
        expect(body.containsKey('ownerUserId'), isFalse);
        // No raw media in body bytes.
        expect(request.bodyBytes, isNot(contains(0xFF)));
        return http.Response(
          jsonEncode(_itemJson(id: 'item_new')),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;

      final created = await ItemsRepository(client).createItem(
        const CreateItem(
          type: ItemType.photo,
          sourceType: SourceType.local,
          sourceRef: 'file:///tmp/a.jpg',
          contentHash: 'abc',
          capturedAt: '2026-07-01T12:00:00.000Z',
        ),
      );
      expect(created.id, 'item_new');
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });

    test('two tokens never observe each other\'s items (tenant isolation)',
        () async {
      Future<List<Item>> listFor(String token, String prefix) async {
        final mock = MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer $token');
          return http.Response(
            jsonEncode([_itemJson(id: '${prefix}_1')]),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final client = ApiClient(
          baseUrl: 'http://api.test',
          tokenProvider: () => token,
          httpClient: mock,
        );
        final items = await ItemsRepository(client).listItems();
        client.close();
        return items;
      }

      final a = await listFor('tok-a', 'a');
      final b = await listFor('tok-b', 'b');
      expect(a.single.id, 'a_1');
      expect(b.single.id, 'b_1');
      expect(a.single.id, isNot(b.single.id));
    });

    test('listItems / createItem never put ownerUserId in body (R10)', () async {
      final mock = MockClient((request) async {
        if (request.method == 'GET') {
          return http.Response(jsonEncode([]), 200);
        }
        return http.Response(
          jsonEncode(_itemJson(id: 'item_x')),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;

      final repo = ItemsRepository(client);
      await repo.listItems();
      await repo.createItem(
        const CreateItem(type: ItemType.photo, sourceType: SourceType.local),
      );
      expect(client.recordedRequests, isNotEmpty);
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });
  });
}
