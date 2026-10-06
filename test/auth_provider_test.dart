import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_desk.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/firebase_sign_in_page.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs.dart';
import 'package:tagkin_desktop/prefs/second_factor_section.dart';
import 'package:tagkin_desktop/auth/phone_number.dart';
import 'package:tagkin_desktop/auth/provider_session.dart';
import 'package:tagkin_desktop/auth/secure_persistor.dart';
import 'package:tagkin_desktop/config/app_config.dart';

void main() {
  test('bootstrap parse keeps only public firebase config', () {
    final parsed = AuthBootstrap.tryParse({
      'providerId': 'firebase',
      'firebase': {
        'apiKey': 'public-key',
        'authDomain': 'app.firebaseapp.com',
        'projectId': 'app',
        'googleClientId': 'client.apps.googleusercontent.com',
      },
    });
    expect(parsed?.isFirebase, isTrue);
    expect(parsed?.firebase?.projectId, 'app');
    expect(parsed?.clerkPublishableKey, isNull);
  });

  test('password sign-in reads the identity toolkit session', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/accounts:signInWithPassword');
      expect(request.url.queryParameters['key'], 'public-key');
      return http.Response(
        jsonEncode({
          'idToken': 'id-1',
          'refreshToken': 'refresh-1',
          'expiresIn': '3600',
          'localId': 'uid-1',
          'email': 'a@example.com',
        }),
        200,
      );
    });
    final session = await signInWithPassword(
      config: const FirebasePublicConfig(
        apiKey: 'public-key',
        authDomain: 'app.firebaseapp.com',
        projectId: 'app',
      ),
      email: 'a@example.com',
      password: 'secret',
      signUp: false,
      httpClient: client,
    );
    expect(session.localId, 'uid-1');
    expect(session.idToken, 'id-1');
  });

  test(
    'changing the global provider clears the previous local session',
    () async {
      final store = MemorySecureKeyValueStore();
      await store.write(key: kActiveAuthProviderKey, value: 'clerk');
      await store.write(key: kFirebaseSessionKey, value: 'old');
      var clearedClerk = false;
      final changed = await reconcileStoredProvider(
        store: store,
        nextProviderId: 'firebase',
        clearClerk: () async => clearedClerk = true,
      );
      expect(changed, isTrue);
      expect(clearedClerk, isTrue);
      expect(await store.read(key: kFirebaseSessionKey), isNull);
      expect(await store.read(key: kActiveAuthProviderKey), 'firebase');
    },
  );

  testWidgets('firebase bootstrap shows the firebase sign-in form', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(
            const AppConfig(apiUrl: 'http://localhost:8787'),
          ),
          authBootstrapProvider.overrideWithValue(
            Future<AuthBootstrap?>.value(
              const AuthBootstrap(
                providerId: 'firebase',
                firebase: FirebasePublicConfig(
                  apiKey: 'public-key',
                  authDomain: 'app.firebaseapp.com',
                  projectId: 'app',
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AuthShell(signedInHome: SizedBox.shrink()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('firebase-email')), findsOneWidget);
    expect(find.byKey(const Key('missing-clerk-config')), findsNothing);
    // No Google client id in bootstrap: no Google button.
    expect(find.byKey(const Key('firebase-google')), findsNothing);
  });

  testWidgets(
    'firebase sign-in shows Continue with Google when bootstrap has a client id',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: FirebaseSignInPage(
            config: const FirebasePublicConfig(
              apiKey: 'public-key',
              authDomain: 'app.firebaseapp.com',
              projectId: 'app',
              googleClientId: 'client.apps.googleusercontent.com',
            ),
            apiUrl: 'http://localhost:8787',
            onSession: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('firebase-google')), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.byKey(const Key('firebase-email')), findsOneWidget);
    },
  );

  testWidgets('firebase password sign-in opens a session without an email code', (
    tester,
  ) async {
    var sessions = 0;
    final client = MockClient((request) async {
      if (request.url.path.contains('signInWithPassword')) {
        return http.Response(
          jsonEncode({
            'idToken': 'id-1',
            'refreshToken': 'refresh-1',
            'expiresIn': '3600',
            'localId': 'uid-1',
            'email': 'a@example.com',
          }),
          200,
        );
      }
      return http.Response('missing', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FirebaseSignInPage(
          config: const FirebasePublicConfig(
            apiKey: 'public-key',
            authDomain: 'app.firebaseapp.com',
            projectId: 'app',
          ),
          apiUrl: 'http://localhost:8787',
          httpClient: client,
          onSession: (_) => sessions += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-email')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('firebase-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('firebase-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 1);
    expect(find.byKey(const Key('firebase-email-code')), findsNothing);
    expect(find.byKey(const Key('firebase-email-me')), findsOneWidget);
  });

  testWidgets('firebase email code is a password alternative', (tester) async {
    var sessions = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/auth/email-code') {
        return http.Response(
          jsonEncode({'emailMasked': 'a...@example.com'}),
          200,
        );
      }
      if (request.url.path == '/auth/email-code/verify') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['code'] != '123456') {
          return http.Response(
            jsonEncode({
              'code': 'email_code_invalid',
              'message': 'That code is wrong.',
            }),
            401,
          );
        }
        return http.Response(jsonEncode({'oobCode': 'oob-1'}), 200);
      }
      if (request.url.path.contains('signInWithEmailLink')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['oobCode'] != 'oob-1') return http.Response('no', 400);
        return http.Response(
          jsonEncode({
            'idToken': 'id-1',
            'refreshToken': 'refresh-1',
            'expiresIn': '3600',
            'localId': 'uid-1',
            'email': 'a@example.com',
            'isNewUser': false,
          }),
          200,
        );
      }
      return http.Response('missing', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FirebaseSignInPage(
          config: const FirebasePublicConfig(
            apiKey: 'public-key',
            authDomain: 'app.firebaseapp.com',
            projectId: 'app',
          ),
          apiUrl: 'http://localhost:8787',
          httpClient: client,
          onSession: (_) => sessions += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-email')),
      'a@example.com',
    );
    await tester.tap(find.byKey(const Key('firebase-email-me')));
    await tester.pumpAndSettle();
    expect(sessions, 0);
    expect(find.byKey(const Key('firebase-email-code')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('firebase-email-code')),
      '000000',
    );
    await tester.tap(find.byKey(const Key('firebase-email-code-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 0);
    expect(find.text('That code is wrong.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('firebase-email-code')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('firebase-email-code-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 1);
  });

  testWidgets('firebase totp is asked only after the password is accepted', (
    tester,
  ) async {
    var sessions = 0;
    final client = MockClient((request) async {
      if (request.url.path.contains('signInWithPassword')) {
        return http.Response(
          jsonEncode({
            'mfaPendingCredential': 'pending-1',
            'mfaInfo': [
              {
                'mfaEnrollmentId': 'enroll-1',
                'displayName': 'Authenticator app',
                'totpInfo': {},
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path.contains('mfaSignIn:finalize')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final totp = body['totpVerificationInfo'] as Map<String, dynamic>;
        if (totp['verificationCode'] != '654321') {
          return http.Response(
            jsonEncode({
              'error': {'message': 'INVALID_CODE'},
            }),
            400,
          );
        }
        return http.Response(
          jsonEncode({
            'idToken': 'id-1',
            'refreshToken': 'refresh-1',
            'expiresIn': '3600',
            'localId': 'uid-1',
            'email': 'a@example.com',
          }),
          200,
        );
      }
      return http.Response('missing', 404);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: FirebaseSignInPage(
          config: const FirebasePublicConfig(
            apiKey: 'public-key',
            authDomain: 'app.firebaseapp.com',
            projectId: 'app',
          ),
          apiUrl: 'http://localhost:8787',
          httpClient: client,
          onSession: (_) => sessions += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-email')),
      'a@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('firebase-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('firebase-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 0);
    expect(find.byKey(const Key('firebase-mfa-code')), findsOneWidget);
    expect(find.byKey(const Key('login-hero')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('firebase-mfa-code')), '000000');
    await tester.tap(find.byKey(const Key('firebase-mfa-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 0);
    expect(find.text('That code is wrong.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('firebase-mfa-code')), '654321');
    await tester.tap(find.byKey(const Key('firebase-mfa-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 1);
  });

  test('require a second factor defaults on', () {
    expect(const DesktopPrefs().requireSecondFactor, isTrue);
    expect(DesktopPrefs.fromJson(const {}).requireSecondFactor, isTrue);
    expect(
      DesktopPrefs.fromJson(const {
        'auth.requireSecondFactor': false,
      }).requireSecondFactor,
      isFalse,
    );
  });

  testWidgets('a saved session does not show the second-factor gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      _gateHost(
        active: false,
        client: MockClient((_) async => http.Response('no', 500)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('library')), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-gate')), findsNothing);
  });

  testWidgets('the text code field says the text can take a minute', (
    tester,
  ) async {
    final session = FirebaseSession(
      idToken: _verifiedToken(),
      refreshToken: 'refresh',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      localId: 'uid-1',
      email: 'a@example.com',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseDeskProvider.overrideWithValue(
            FirebaseDesk(
              apiUrl: 'http://localhost:8787',
              config: const FirebasePublicConfig(
                apiKey: 'public-key',
                authDomain: 'app.firebaseapp.com',
                projectId: 'app',
              ),
              session: session,
              onSession: (_) {},
              onSignOut: () async {},
            ),
          ),
        ],
        child: const MaterialApp(
          home: SecondFactorSection(gate: true, showSmsCodeField: true),
        ),
      ),
    );
    expect(find.byKey(const Key('settings-sms-code')), findsOneWidget);
    expect(find.text(kTextCodeDelayNote), findsOneWidget);
  });

  testWidgets('a fresh sign-in with no factor shows the enrollment gate', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.contains('accounts:lookup')) {
        return http.Response(jsonEncode({'users': <Object>[]}), 200);
      }
      return http.Response('no', 404);
    });
    await tester.pumpWidget(_gateHost(active: true, client: client));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-mfa-gate')), findsOneWidget);
    expect(find.byKey(const Key('login-hero')), findsOneWidget);
    expect(find.text('Show second factors'), findsNothing);
    expect(find.byKey(const Key('settings-add-totp')), findsOneWidget);
    expect(find.byKey(const Key('library')), findsNothing);
  });

  testWidgets('a fresh sign-in that already has a factor opens the library', (
    tester,
  ) async {
    var cleared = 0;
    final client = MockClient((request) async {
      if (request.url.path.contains('accounts:lookup')) {
        return http.Response(
          jsonEncode({
            'users': [
              {
                'mfaInfo': [
                  {
                    'mfaEnrollmentId': 'enroll-1',
                    'totpInfo': <String, Object>{},
                    'displayName': 'Authenticator app',
                  },
                ],
              },
            ],
          }),
          200,
        );
      }
      return http.Response('no', 404);
    });
    await tester.pumpWidget(
      _gateHost(active: true, client: client, onCleared: () => cleared += 1),
    );
    await tester.pumpAndSettle();
    expect(cleared, 1);
    expect(find.byKey(const Key('library')), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-gate')), findsNothing);
  });
}

Widget _gateHost({
  required bool active,
  required http.Client client,
  VoidCallback? onCleared,
}) {
  final session = FirebaseSession(
    idToken: _verifiedToken(),
    refreshToken: 'refresh',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    localId: 'uid-1',
    email: 'a@example.com',
  );
  return ProviderScope(
    overrides: [
      firebaseDeskProvider.overrideWithValue(
        FirebaseDesk(
          apiUrl: 'http://localhost:8787',
          config: const FirebasePublicConfig(
            apiKey: 'public-key',
            authDomain: 'app.firebaseapp.com',
            projectId: 'app',
          ),
          session: session,
          onSession: (_) {},
          onSignOut: () async {},
        ),
      ),
    ],
    child: MaterialApp(
      home: SecondFactorGate(
        active: active,
        httpClient: client,
        onCleared: onCleared ?? () {},
        child: const Text('library', key: Key('library')),
      ),
    ),
  );
}

String _verifiedToken() {
  String part(Object value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${part({'alg': 'none'})}.${part({'email_verified': true})}.x';
}
