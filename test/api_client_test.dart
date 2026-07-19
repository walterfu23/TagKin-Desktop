import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/me_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';

void main() {
  group('ApiClient + MeRepository', () {
    test('valid token resolves /me into an Account', () async {
      final mock = MockClient((request) async {
        expect(request.url.path, '/me');
        expect(request.headers['Authorization'], 'Bearer tok-a');
        return http.Response(
          jsonEncode({
            'id': 'acc_1',
            'email': 'a@example.com',
            'createdAt': '2026-07-18T00:00:00.000Z',
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
      final account = await MeRepository(client).getMe();
      expect(account.id, 'acc_1');
      expect(account.email, 'a@example.com');
      client.close();
    });

    test('401 surfaces UnauthorizedException exactly once (no retry)', () async {
      var calls = 0;
      final mock = MockClient((request) async {
        calls += 1;
        return http.Response(
          jsonEncode({'code': 'unauthorized', 'message': 'Expired'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'expired',
        httpClient: mock,
      );
      await expectLater(
        MeRepository(client).getMe(),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(calls, 1);
      client.close();
    });

    test('never puts ownerUserId in a request body (R10)', () async {
      final mock = MockClient((request) async {
        return http.Response('{}', 200);
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      )..recordRequests = true;

      await client.post('/items', body: {
        'type': 'photo',
        'sourceType': 'local',
      });
      expect(client.recordedRequests, isNotEmpty);
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
      }
      client.close();
    });

    test('JSON Content-Type only — no multipart/bytes to tagkin-api (R1)', () async {
      final mock = MockClient((request) async {
        expect(request.headers['Content-Type'], 'application/json');
        expect(request.bodyBytes, isNot(contains(0xFF))); // not raw media
        return http.Response('{}', 200);
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok',
        httpClient: mock,
      );
      await client.post('/items', body: {'type': 'photo', 'sourceType': 'local'});
      client.close();
    });

    test('two tokens resolve distinct accounts (tenant isolation fixture)', () async {
      Account parse(String id) => Account(
            id: id,
            email: '$id@example.com',
            createdAt: '2026-07-18T00:00:00.000Z',
          );

      Future<Account> meFor(String token, String accountId) async {
        final mock = MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer $token');
          final a = parse(accountId);
          return http.Response(
            jsonEncode(a.toJson()),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final client = ApiClient(
          baseUrl: 'http://api.test',
          tokenProvider: () => token,
          httpClient: mock,
        );
        final account = await MeRepository(client).getMe();
        client.close();
        return account;
      }

      final a = await meFor('tok-a', 'acc_a');
      final b = await meFor('tok-b', 'acc_b');
      expect(a.id, 'acc_a');
      expect(b.id, 'acc_b');
      expect(a.id, isNot(b.id));
    });
  });
}
