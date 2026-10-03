import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/google_loopback.dart';

Future<int> _get(String url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(url));
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

void main() {
  test('loopback accepts the code when state matches', () async {
    final loopback = await GoogleLoopback.start();
    expect(loopback.redirectUri, startsWith('http://127.0.0.1:'));
    final status = await _get(
      '${loopback.redirectUri}/?code=abc&state=${loopback.state}',
    );
    expect(status, 200);
    expect(await loopback.code, 'abc');
  });

  test('loopback ignores a wrong state and favicon, then accepts the real one',
      () async {
    final loopback = await GoogleLoopback.start();
    expect(await _get('${loopback.redirectUri}/favicon.ico'), 404);
    expect(await _get('${loopback.redirectUri}/?code=evil&state=nope'), 400);
    expect(
      await _get('${loopback.redirectUri}/?code=good&state=${loopback.state}'),
      200,
    );
    expect(await loopback.code, 'good');
  });

  test('loopback surfaces a denied consent as cancelled', () async {
    final loopback = await GoogleLoopback.start();
    final result = loopback.code;
    await _get(
      '${loopback.redirectUri}/?error=access_denied&state=${loopback.state}',
    );
    await expectLater(
      result,
      throwsA(
        isA<GoogleLoopbackException>()
            .having((e) => e.message, 'message', contains('cancelled')),
      ),
    );
  });

  test('loopback times out and cancel completes with an error', () async {
    final slow = await GoogleLoopback.start(
      timeout: const Duration(milliseconds: 50),
    );
    await expectLater(slow.code, throwsA(isA<GoogleLoopbackException>()));

    final cancelled = await GoogleLoopback.start();
    final result = cancelled.code;
    await cancelled.cancel();
    await expectLater(result, throwsA(isA<GoogleLoopbackException>()));
  });

  test('authorize uri carries the loopback redirect, PKCE and state', () {
    final uri = googleAuthorizeUri(
      clientId: 'cid',
      redirectUri: 'http://127.0.0.1:5555',
      codeChallenge: 'chal',
      state: 's1',
    );
    expect(uri.host, 'accounts.google.com');
    expect(uri.queryParameters['redirect_uri'], 'http://127.0.0.1:5555');
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(uri.queryParameters['state'], 's1');
    expect(uri.queryParameters.containsKey('client_secret'), isFalse);
  });

  test('google code is exchanged through the TagKin API, then Firebase',
      () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      seen.add('${request.url.host}${request.url.path}');
      if (request.url.path == '/auth/google/token') {
        final body = jsonDecode(request.body) as Map;
        expect(body['code'], 'abc');
        expect(body['codeVerifier'], 'ver');
        expect(body['redirectUri'], 'http://127.0.0.1:5555');
        expect(body.containsKey('client_secret'), isFalse);
        return http.Response(jsonEncode({'idToken': 'google-id'}), 200);
      }
      expect(request.url.path, '/v1/accounts:signInWithIdp');
      expect(jsonDecode(request.body)['postBody'], contains('google-id'));
      return http.Response(
        jsonEncode({
          'idToken': 'fb-id',
          'refreshToken': 'fb-refresh',
          'expiresIn': '3600',
          'localId': 'uid-g',
          'email': 'g@example.com',
        }),
        200,
      );
    });
    final session = await signInWithGoogleCode(
      config: const FirebasePublicConfig(
        apiKey: 'public-key',
        authDomain: 'app.firebaseapp.com',
        projectId: 'app',
        googleClientId: 'cid',
      ),
      apiUrl: 'http://localhost:8787',
      code: 'abc',
      codeVerifier: 'ver',
      redirectUri: 'http://127.0.0.1:5555',
      httpClient: client,
    );
    expect(session.localId, 'uid-g');
    expect(seen.first, 'localhost/auth/google/token');
    expect(seen.any((s) => s.contains('oauth2.googleapis.com')), isFalse);
  });

  test('a rejected exchange surfaces the API message', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({'code': 'bad_request', 'message': 'Google is off.'}),
          400,
        ));
    await expectLater(
      signInWithGoogleCode(
        config: const FirebasePublicConfig(
          apiKey: 'k',
          authDomain: 'd',
          projectId: 'p',
        ),
        apiUrl: 'http://localhost:8787',
        code: 'abc',
        codeVerifier: 'ver',
        redirectUri: 'http://127.0.0.1:5555',
        httpClient: client,
      ),
      throwsA(
        isA<FirebaseAuthException>()
            .having((e) => e.message, 'message', 'Google is off.'),
      ),
    );
  });
}
