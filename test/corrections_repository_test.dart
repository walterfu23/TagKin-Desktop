import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/corrections_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

Map<String, dynamic> _tagJson({
  required String id,
  String value = 'picnic',
  String dimension = 'what',
}) =>
    {
      'id': id,
      'itemId': 'item_1',
      'keyPeriodId': null,
      'dimension': dimension,
      'value': value,
      'source': 'human',
      'status': 'active',
      'correctedFromTagId': null,
      'confidence': null,
      'provider': null,
      'modelId': null,
      'schemaVersion': 1,
      'createdAt': '2026-07-20T12:00:00.000Z',
    };

Map<String, dynamic> _correctionJson({
  required String id,
  String targetType = 'tag',
  String targetId = 'tag_1',
}) =>
    {
      'id': id,
      'targetType': targetType,
      'targetId': targetId,
      'previousValue': 'old',
      'newValue': 'new',
      'source': 'human',
      'createdAt': '2026-07-20T12:00:00.000Z',
    };

Map<String, dynamic> _itemJson({String? capturedAt}) => {
      'id': 'item_1',
      'type': 'photo',
      'sourceType': 'local',
      'sourceRef': 'file:///tmp/a.jpg',
      'analysisRef': null,
      'analysisRefState': 'pending',
      'contentHash': 'hash',
      'perceptualHash': null,
      'dedupOfItemId': null,
      'capturedAt': capturedAt,
      'processingStatus': 'tagged',
      'schemaVersion': 1,
      'createdAt': '2026-07-19T00:00:00.000Z',
    };

void main() {
  group('CorrectionsRepository', () {
    test('addTag POSTs AddTag body without owner fields (R10)', () async {
      late ApiRequestRecord recorded;
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items/item_1/tags');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['dimension'], 'what');
        expect(body['value'], 'picnic');
        expect(body.containsKey('ownerUserId'), isFalse);
        expect(body.containsKey('accountId'), isFalse);
        expect(body.containsKey('source'), isFalse);
        return http.Response(
          jsonEncode({
            'tag': _tagJson(id: 'tag_new'),
            'correction': _correctionJson(id: 'corr_1', targetId: 'tag_new'),
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
      final result = await CorrectionsRepository(client).addTag(
        'item_1',
        const AddTag(dimension: 'what', value: 'picnic'),
      );
      expect(result.tag.value, 'picnic');
      expect(result.correction.id, 'corr_1');
      recorded = client.recordedRequests.single;
      expect(recorded.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('editTag PATCHes /tags/{id}', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/tags/tag_1');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['value'], 'hiking');
        expect(body.containsKey('ownerUserId'), isFalse);
        return http.Response(
          jsonEncode({
            'tag': _tagJson(id: 'tag_2', value: 'hiking'),
            'correction': _correctionJson(id: 'corr_2', targetId: 'tag_2'),
          }),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final result = await CorrectionsRepository(client).editTag(
        'tag_1',
        const EditTag(value: 'hiking'),
      );
      expect(result.tag.value, 'hiking');
      client.close();
    });

    test('removeTag DELETEs /tags/{id}', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/tags/tag_1');
        return http.Response(
          jsonEncode({
            'tag': {..._tagJson(id: 'tag_1'), 'status': 'removed'},
            'correction': _correctionJson(id: 'corr_3'),
          }),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final result = await CorrectionsRepository(client).removeTag('tag_1');
      expect(result.tag.status, TagStatus.removed);
      client.close();
    });

    test('correctCapturedAt PATCHes metadata only', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/items/item_1/captured-at');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, ['capturedAt']);
        return http.Response(
          jsonEncode({
            'item': _itemJson(capturedAt: '2026-07-04T15:00:00.000Z'),
            'correction': _correctionJson(
              id: 'corr_ca',
              targetType: 'item_captured_at',
              targetId: 'item_1',
            ),
          }),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final result = await CorrectionsRepository(client).correctCapturedAt(
        'item_1',
        const CorrectCapturedAt(capturedAt: '2026-07-04T15:00:00.000Z'),
      );
      expect(result.item.capturedAt, '2026-07-04T15:00:00.000Z');
      client.close();
    });

    test('correctKeyPeriodBounds PATCHes startMs/endMs', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/key-periods/kp_1');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['startMs'], 1000);
        expect(body['endMs'], 5000);
        return http.Response(
          jsonEncode({
            'keyPeriod': {
              'id': 'kp_1',
              'itemId': 'item_1',
              'startMs': 1000,
              'endMs': 5000,
              'tags': [],
            },
            'correction': _correctionJson(
              id: 'corr_kp',
              targetType: 'key_period_bounds',
              targetId: 'kp_1',
            ),
          }),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final result = await CorrectionsRepository(client).correctKeyPeriodBounds(
        'kp_1',
        const CorrectKeyPeriodBounds(startMs: 1000, endMs: 5000),
      );
      expect(result.keyPeriod.startMs, 1000);
      client.close();
    });

    test('undoCorrection POSTs /corrections/{id}/undo', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/corrections/corr_1/undo');
        expect(request.body.isEmpty || request.body == 'null', isTrue);
        return http.Response(
          jsonEncode({
            'correction': _correctionJson(id: 'corr_1'),
            'restored': {
              'kind': 'tag',
              'tag': _tagJson(id: 'tag_1', value: 'old'),
            },
          }),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final result =
          await CorrectionsRepository(client).undoCorrection('corr_1');
      expect(result.restored.kind, 'tag');
      expect(result.restored.tag!.value, 'old');
      client.close();
    });

    test('foreign tag id surfaces 404 (R10)', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 'not_found', 'message': 'Not found'}),
          404,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      expect(
        () => CorrectionsRepository(client).removeTag('foreign'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      client.close();
    });
  });
}
