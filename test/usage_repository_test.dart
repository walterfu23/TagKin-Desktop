import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/usage_repository.dart';

void main() {
  group('UsageRepository', () {
    test('getUsage returns UsageSummary from GET /usage', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/usage');
        expect(request.headers['Authorization'], 'Bearer tok-a');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'softLimitCents': 1000,
            'hardLimitCents': 2000,
            'reservedCents': 100,
            'spentCents': 200,
            'killSwitch': {'enabled': false, 'reason': null},
            'softLimitExceeded': false,
            'pauseReason': null,
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

      final summary = await UsageRepository(client).getUsage();
      expect(summary.softLimitCents, 1000);
      expect(summary.hardLimitCents, 2000);
      expect(summary.reservedCents, 100);
      expect(summary.spentCents, 200);
      expect(summary.killSwitch.enabled, isFalse);
      expect(client.recordedRequests, hasLength(1));
      expect(client.recordedRequests.single.body, isNull);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('getUsage never sends ownerUserId / body (R10 / R1)', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.bodyBytes, isEmpty);
        return http.Response(
          jsonEncode({
            'softLimitCents': 1,
            'hardLimitCents': 2,
            'reservedCents': 0,
            'spentCents': 0,
            'killSwitch': {'enabled': false},
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

      await UsageRepository(client).getUsage();
      for (final r in client.recordedRequests) {
        expect(r.bodyContainsOwnerField, isFalse);
        expect(r.body, isNull);
      }
      client.close();
    });

    test('two tokens never observe each other\'s usage (tenant isolation)',
        () async {
      Future<int> spentFor(String token, int spent) async {
        final mock = MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer $token');
          return http.Response(
            jsonEncode({
              'softLimitCents': 1000,
              'hardLimitCents': 2000,
              'reservedCents': 0,
              'spentCents': spent,
              'killSwitch': {'enabled': false},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });
        final client = ApiClient(
          baseUrl: 'http://api.test',
          tokenProvider: () => token,
          httpClient: mock,
        );
        final summary = await UsageRepository(client).getUsage();
        client.close();
        return summary.spentCents;
      }

      expect(await spentFor('tok-a', 111), 111);
      expect(await spentFor('tok-b', 222), 222);
    });
  });
}
