import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/credits_repository.dart';

void main() {
  group('CreditsRepository', () {
    test('listPacks GETs /credits/packs with bearer and no owner field',
        () async {
      final mock = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/credits/packs');
        expect(request.headers['Authorization'], 'Bearer tok-a');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({
            'packs': [
              {
                'packId': 'pack20',
                'priceUsdCents': 2000,
                'credits': 2000,
                'debtCreditsToClear': 0,
                'netCredits': 2000,
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
      final listed = await CreditsRepository(client).listPacks();
      expect(listed.packs, hasLength(1));
      expect(listed.packs.single.packId, 'pack20');
      expect(listed.packs.single.netCredits, 2000);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('createPurchase POSTs packId only — never accountId or credits',
        () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/credits/purchases');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, ['packId']);
        expect(body['packId'], 'pack20');
        expect(body.containsKey('accountId'), isFalse);
        expect(body.containsKey('credits'), isFalse);
        return http.Response(
          jsonEncode({
            'purchaseId': 'pur_1',
            'status': 'pending',
            'packId': 'pack20',
            'priceUsdCents': 2000,
            'currency': 'usd',
            'credits': 2000,
            'maxDebtCreditsToClear': 0,
            'quotedNetCredits': 2000,
            'checkoutUrl': 'https://checkout.stripe.test/cs_1',
            'remainingCredits': 0,
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = ApiClient(
        baseUrl: 'http://api.test',
        tokenProvider: () => 'tok-a',
        httpClient: mock,
      )..recordRequests = true;
      final created =
          await CreditsRepository(client).createPurchase(packId: 'pack20');
      expect(created.checkoutUrl, 'https://checkout.stripe.test/cs_1');
      expect(created.credits, 2000);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('previewRedeem POSTs code only — never accountId', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/credits/redemptions/preview');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, ['code']);
        expect(body['code'], 'TK-ABCD-EFGH-JKLM');
        expect(body.containsKey('accountId'), isFalse);
        return http.Response(
          jsonEncode({
            'packId': 'pack20',
            'credits': 2000,
            'debtCreditsToClear': 1200,
            'netCredits': 800,
            'expiresAt': '2099-01-01T00:00:00.000Z',
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
      final preview =
          await CreditsRepository(client).previewRedeem('TK-ABCD-EFGH-JKLM');
      expect(preview.debtCreditsToClear, 1200);
      expect(preview.netCredits, 800);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });

    test('redeem POSTs code only — never accountId or credits', () async {
      final mock = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/credits/redemptions');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys, ['code']);
        expect(body.containsKey('accountId'), isFalse);
        expect(body.containsKey('credits'), isFalse);
        return http.Response(
          jsonEncode({
            'packId': 'pack20',
            'credits': 2000,
            'debtPaidCredits': 0,
            'netCredits': 2000,
            'remainingCredits': 2000,
            'creditDebt': 0,
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
      final applied = await CreditsRepository(client).redeem('TK-ABCD-EFGH-JKLM');
      expect(applied.remainingCredits, 2000);
      expect(client.recordedRequests.single.bodyContainsOwnerField, isFalse);
      client.close();
    });
  });
}
