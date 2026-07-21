import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
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

Map<String, dynamic> _jobJson({
  required String id,
  required String itemId,
  String state = 'queued',
}) =>
    {
      'id': id,
      'itemId': itemId,
      'kind': 'analyze',
      'state': state,
      'attempts': 0,
      'pipelineVersion': 1,
      'createdAt': '2026-07-20T00:00:00.000Z',
      'updatedAt': '2026-07-20T00:00:00.000Z',
    };

Map<String, dynamic> _exportJson({required String itemId}) => {
      'items': [_itemJson(id: itemId)],
      'tags': <dynamic>[],
      'persons': <dynamic>[],
      'comments': <dynamic>[],
      'corrections': <dynamic>[],
      'exportedAt': '2026-07-20T12:00:00.000Z',
    };

void main() {
  group('JobsRepository', () {
    test('analyzeItem POSTs /items/{id}/analyze with empty body (R1/R10)',
        () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items/item_a/analyze');
        expect(request.headers['Authorization'], 'Bearer tok-a');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'item': _itemJson(id: 'item_a', status: 'tagged'),
            'tagIds': ['tag_1'],
            'provider': 'stub',
            'modelId': 'stub-model',
            'escalated': false,
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
      final result = await JobsRepository(client).analyzeItem('item_a');
      expect(result.item.id, 'item_a');
      expect(result.tagIds, ['tag_1']);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('analyzeItem surfaces 409 BudgetExceeded without auto-retry', () async {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response(
          jsonEncode({
            'code': 'budget_exceeded',
            'message': 'Hard budget exceeded',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      await expectLater(
        JobsRepository(client).analyzeItem('item_a'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.message, 'message', 'Hard budget exceeded'),
        ),
      );
      expect(calls, 1);
      client.close();
    });

    test('listItemJobs returns jobs; foreign id surfaces 404 (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/items/foreign/jobs');
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
        JobsRepository(client).listItemJobs('foreign'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      client.close();
    });

    test('listItemJobs parses Job array', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/items/item_a/jobs');
        return http.Response(
          jsonEncode([
            _jobJson(id: 'job_2', itemId: 'item_a', state: 'completed'),
            _jobJson(id: 'job_1', itemId: 'item_a', state: 'failed'),
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
      final jobs = await JobsRepository(client).listItemJobs('item_a');
      expect(jobs.map((j) => j.id), ['job_2', 'job_1']);
      expect(jobs.first.state, JobState.completed);
      client.close();
    });

    test('cancelItem POSTs /cancel with no owner field (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items/item_a/cancel');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'item': _itemJson(id: 'item_a', status: 'cancelled'),
            'job': _jobJson(id: 'job_c', itemId: 'item_a', state: 'cancelled'),
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
      final result = await JobsRepository(client).cancelItem('item_a');
      expect(result.item.processingStatus, ProcessingStatus.cancelled);
      expect(result.job?.state, JobState.cancelled);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('deleteItem DELETEs /items/{id} with no body (R1/R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/items/item_a');
        expect(request.body, isEmpty);
        return http.Response('', 204);
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok-a',
        httpClient: mock,
      )..recordRequests = true;
      await JobsRepository(client).deleteItem('item_a');
      expect(client.recordedRequests.single.body, isNull);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('exportLibrary returns knowledge only — no byte fields (R1)',
        () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/export');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode(_exportJson(itemId: 'item_a')),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok-a',
        httpClient: mock,
      )..recordRequests = true;
      final exported = await JobsRepository(client).exportLibrary();
      expect(exported.items.single.id, 'item_a');
      final json = exported.toJson();
      expect(json.containsKey('bytes'), isFalse);
      expect(json.containsKey('blob'), isFalse);
      expect(json.containsKey('data'), isFalse);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('two tokens never observe each other\'s jobs (tenant isolation)',
        () async {
      Future<List<Job>> listFor(String token) async {
        final mock = MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer $token');
          if (token == 'tok-a') {
            return http.Response(
              jsonEncode([
                _jobJson(id: 'job_a', itemId: 'item_a', state: 'completed'),
              ]),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(jsonEncode([]), 200);
        });
        final client = ApiClient(
          baseUrl: 'http://api.test',
          tokenProvider: () => token,
          httpClient: mock,
        );
        final jobs = await JobsRepository(client).listItemJobs('item_a');
        client.close();
        return jobs;
      }

      final a = await listFor('tok-a');
      final b = await listFor('tok-b');
      expect(a.map((j) => j.id), ['job_a']);
      expect(b, isEmpty);
    });
  });
}
