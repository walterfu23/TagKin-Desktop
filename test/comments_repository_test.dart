import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/comments_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

Map<String, dynamic> _commentJson({
  required String id,
  String? itemId = 'item_1',
  String? keyPeriodId,
  String authorUserId = 'acc_server',
  String body = 'hello',
}) =>
    {
      'id': id,
      'itemId': itemId,
      'keyPeriodId': keyPeriodId,
      'authorUserId': authorUserId,
      'body': body,
      'deletedAt': null,
      'createdAt': '2026-07-20T12:00:00.000Z',
      'updatedAt': null,
    };

void main() {
  group('CommentsRepository', () {
    test('listItemComments GETs /items/{id}/comments', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/items/item_1/comments');
        return http.Response(
          jsonEncode([
            _commentJson(id: 'c1'),
            _commentJson(id: 'c2', keyPeriodId: 'kp_1', body: 'kp note'),
          ]),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final list = await CommentsRepository(client).listItemComments('item_1');
      expect(list.map((c) => c.id), ['c1', 'c2']);
      expect(list[1].keyPeriodId, 'kp_1');
      client.close();
    });

    test('createItemComment body is text-only; author from server (R10)',
        () async {
      late String? recordedBody;
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/items/item_1/comments');
        recordedBody = request.body;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, ['body']);
        expect(body.containsKey('authorUserId'), isFalse);
        expect(body.containsKey('ownerUserId'), isFalse);
        expect(body.containsKey('itemId'), isFalse);
        return http.Response(
          jsonEncode(_commentJson(id: 'c_new', body: 'nice')),
          201,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;
      final created = await CommentsRepository(client).createItemComment(
        'item_1',
        const CreateComment(body: 'nice'),
      );
      expect(created.authorUserId, 'acc_server');
      expect(created.body, 'nice');
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      expect(recordedBody, isNot(contains('authorUserId')));
      client.close();
    });

    test('createKeyPeriodComment attaches via path only (R10)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/key-periods/kp_1/comments');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, ['body']);
        expect(body.containsKey('itemId'), isFalse);
        expect(body.containsKey('keyPeriodId'), isFalse);
        return http.Response(
          jsonEncode(
            _commentJson(id: 'c_kp', keyPeriodId: 'kp_1', body: 'span note'),
          ),
          201,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final created = await CommentsRepository(client).createKeyPeriodComment(
        'kp_1',
        const CreateComment(body: 'span note'),
      );
      expect(created.keyPeriodId, 'kp_1');
      client.close();
    });

    test('editComment PATCHes body only', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/comments/c1');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body, {'body': 'updated'});
        return http.Response(
          jsonEncode(_commentJson(id: 'c1', body: 'updated')),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final updated = await CommentsRepository(client).editComment(
        'c1',
        const EditComment(body: 'updated'),
      );
      expect(updated.body, 'updated');
      client.close();
    });

    test('deleteComment soft-deletes', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/comments/c1');
        return http.Response(
          jsonEncode({
            ..._commentJson(id: 'c1'),
            'deletedAt': '2026-07-20T14:00:00.000Z',
          }),
          200,
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      final deleted = await CommentsRepository(client).deleteComment('c1');
      expect(deleted.deletedAt, isNotNull);
      client.close();
    });

    test('foreign comment id surfaces 404 (R10)', () async {
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
        () => CommentsRepository(client).deleteComment('foreign'),
        throwsA(
          isA<ApiException>().having((e) => e.statusCode, 'status', 404),
        ),
      );
      client.close();
    });
  });
}
