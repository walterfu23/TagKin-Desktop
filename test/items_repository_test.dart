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

    test('getKnowledge returns approved projection; foreign id 404 (R10)',
        () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/items/item_1/knowledge');
        expect(request.headers['Authorization'], 'Bearer tok-a');
        return http.Response(
          jsonEncode({
            'item': _itemJson(id: 'item_1', status: 'tagged'),
            'tags': [
              {
                'id': 'tag_1',
                'itemId': 'item_1',
                'keyPeriodId': null,
                'dimension': 'what',
                'value': 'picnic',
                'source': 'model',
                'status': 'active',
                'correctedFromTagId': null,
                'confidence': 0.91,
                'provider': 'stub',
                'modelId': 'stub-model',
                'schemaVersion': 1,
                'createdAt': '2026-07-19T00:00:00.000Z',
              },
            ],
            'keyPeriods': [],
            'appearances': [],
            'corrections': [],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok-a',
        httpClient: mock,
      );
      final knowledge = await ItemsRepository(client).getKnowledge('item_1');
      expect(knowledge.item.id, 'item_1');
      expect(knowledge.tags.single.value, 'picnic');
      expect(knowledge.tags.single.dimension, 'what');
      client.close();
    });

    test('getKnowledge foreign id surfaces 404 (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/items/foreign/knowledge');
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
        ItemsRepository(client).getKnowledge('foreign'),
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

    test(
        'recordPrePassResult posts vectors/metadata only — no bytes, no owner '
        '(R1/R5/R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items/item_1/pre-pass-result');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('ownerUserId'), isFalse);
        expect(body.containsKey('bytes'), isFalse);
        expect(body.containsKey('blob'), isFalse);
        expect(body.containsKey('base64'), isFalse);
        expect(body['contentHash'], 'abc');
        expect(body['appearances'], isA<List<dynamic>>());
        final emb = (body['appearances'] as List).first as Map<String, dynamic>;
        expect((emb['embedding'] as List).length, 512);
        return http.Response(
          jsonEncode({
            'item': _itemJson(id: 'item_1'),
            'keyPeriodIds': <String>[],
            'appearanceIds': <String>['ap_1'],
            'tagIds': <String>[],
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

      final response = await ItemsRepository(client).recordPrePassResult(
        'item_1',
        PrePassResult(
          contentHash: 'abc',
          perceptualHash: '0123456789abcdef',
          appearances: [
            PrePassAppearanceInput(
              embedding: List<double>.filled(512, 0.01),
              embeddingModelId: 'stub-face-embed-v1',
            ),
          ],
        ),
      );
      expect(response.item.id, 'item_1');
      expect(response.appearanceIds, ['ap_1']);
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });

    test(
        'createUploadGrant posts mimeType only — no key, no owner, no bytes '
        '(R8/R10/R1)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items/item_1/upload-grant');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'mimeType'});
        expect(body['mimeType'], 'image/jpeg');
        expect(body.containsKey('ownerUserId'), isFalse);
        expect(body.containsKey('apiKey'), isFalse);
        return http.Response(
          jsonEncode({
            'uploadUrl': 'https://stub.tagkin.test/upload',
            'expiresAt': '2026-07-19T12:00:00.000Z',
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;

      final grant = await ItemsRepository(client).createUploadGrant(
        'item_1',
        const CreateUploadGrant(mimeType: 'image/jpeg'),
      );
      expect(grant.uploadUrl, 'https://stub.tagkin.test/upload');
      expect(grant.toJson().containsKey('apiKey'), isFalse);
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });

    test(
        'recordAnalysisRef posts analysisRef only — no bytes, no owner '
        '(R1/R4/R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items/item_1/analysis-ref');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'analysisRef'});
        expect(body['analysisRef'], 'files/abc');
        expect(body.containsKey('bytes'), isFalse);
        expect(body.containsKey('ownerUserId'), isFalse);
        return http.Response(
          jsonEncode(_itemJson(id: 'item_1')
            ..['analysisRef'] = 'files/abc'
            ..['analysisRefState'] = 'ready'
            ..['processingStatus'] = 'awaiting_model_access'),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;

      final item = await ItemsRepository(client).recordAnalysisRef(
        'item_1',
        const RecordAnalysisRef(analysisRef: 'files/abc'),
      );
      expect(item.analysisRef, 'files/abc');
      expect(item.analysisRefState, AnalysisRefState.ready);
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });
  });
}
