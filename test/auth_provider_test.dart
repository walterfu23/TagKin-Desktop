import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:tagkin_desktop/persons/collections_controller.dart';
import 'package:tagkin_desktop/persons/collections_store.dart';
import 'package:tagkin_desktop/prefs/desktop_prefs_controller.dart';

import 'fake_comments_repository.dart';
import 'fake_items_repository.dart';
import 'fake_jobs_repository.dart';
import 'fake_persons_repository.dart';
import 'fake_usage_repository.dart';

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
      await store.write(key: kFirebaseGateKey, value: kFirebaseGateNew);
      var clearedClerk = false;
      final changed = await reconcileStoredProvider(
        store: store,
        nextProviderId: 'firebase',
        clearClerk: () async => clearedClerk = true,
      );
      expect(changed, isTrue);
      expect(clearedClerk, isTrue);
      expect(await store.read(key: kFirebaseSessionKey), isNull);
      expect(await store.read(key: kFirebaseGateKey), isNull);
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

  testWidgets(
    'firebase password sign-in opens a session without an email code',
    (tester) async {
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
      expect(find.byKey(const Key('firebase-password')), findsNothing);
      expect(find.byKey(const Key('firebase-use-password')), findsOneWidget);
      expect(find.byKey(const Key('firebase-email-me')), findsOneWidget);
      await tester.tap(find.byKey(const Key('firebase-use-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('firebase-password')),
        'secret',
      );
      await tester.tap(find.byKey(const Key('firebase-submit')));
      await tester.pumpAndSettle();
      expect(sessions, 1);
      expect(find.byKey(const Key('firebase-email-code')), findsNothing);
    },
  );

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
        return _totpFinalizeResponse(request, code: '654321');
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
    await tester.tap(find.byKey(const Key('firebase-use-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('firebase-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 0);
    expect(find.byKey(const Key('firebase-mfa-code')), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Authenticator app'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('firebase-mfa-add-phone')),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Authenticator app'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-mfa-code')), findsOneWidget);
    expect(find.byKey(const Key('login-hero')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('firebase-mfa-code')),
      '000000',
    );
    await tester.tap(find.byKey(const Key('firebase-mfa-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 0);
    expect(find.text('That code is wrong.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('firebase-mfa-code')),
      '654321',
    );
    await tester.tap(find.byKey(const Key('firebase-mfa-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 1);
  });

  testWidgets('a phone and an authenticator are both offered at sign-in', (
    tester,
  ) async {
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
              {'mfaEnrollmentId': 'enroll-2', 'phoneInfo': '+XXXXXXXX0100'},
            ],
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
          onSession: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-email')),
      'a@example.com',
    );
    await tester.tap(find.byKey(const Key('firebase-use-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('firebase-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-mfa-code')), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Authenticator app'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Text +XXXXXXXX0100'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('firebase-mfa-factor-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-mfa-code')), findsOneWidget);
    expect(find.text('Send text'), findsOneWidget);

    await tester.tap(find.byKey(const Key('firebase-mfa-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-mfa-factor-0')), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-factor-1')), findsOneWidget);
  });

  testWidgets('a phone-only account can add an authenticator after the text', (
    tester,
  ) async {
    var add = 0;
    final client = MockClient((request) async {
      if (request.url.path.contains('signInWithPassword')) {
        return http.Response(
          jsonEncode({
            'mfaPendingCredential': 'pending-1',
            'mfaInfo': [
              {'mfaEnrollmentId': 'enroll-2', 'phoneInfo': '+XXXXXXXX0100'},
            ],
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
          onSession: (_) {},
          onAddAuthenticator: () => add += 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-email')),
      'a@example.com',
    );
    await tester.tap(find.byKey(const Key('firebase-use-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('firebase-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-mfa-code')), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Send text +XXXXXXXX0100'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('firebase-mfa-add-authenticator')),
      findsOneWidget,
    );
    expect(add, 0);

    await tester.tap(find.byKey(const Key('firebase-mfa-add-authenticator')));
    await tester.pumpAndSettle();
    expect(find.text('Second factor'), findsOneWidget);
    expect(
      find.byKey(const Key('firebase-mfa-add-authenticator')),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Send text +XXXXXXXX0100'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Enter the code from the text first. Then you can add an authenticator app.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('firebase-mfa-code')), findsNothing);
    expect(find.text('Send text'), findsOneWidget);
    expect(add, 0);

    await tester.tap(find.byKey(const Key('firebase-mfa-choice-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-email')), findsOneWidget);
  });

  testWidgets('an authenticator-only account can add a phone number', (
    tester,
  ) async {
    var addPhone = 0;
    String? enrolledPhone;
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
        return _totpFinalizeResponse(request);
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
          onAddPhone: (phone) {
            addPhone += 1;
            enrolledPhone = phone;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-email')),
      'a@example.com',
    );
    await tester.tap(find.byKey(const Key('firebase-use-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('firebase-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-mfa-code')), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Authenticator app'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('firebase-mfa-add-phone')),
      findsOneWidget,
    );
    expect(addPhone, 0);

    await tester.tap(find.byKey(const Key('firebase-mfa-add-phone')));
    await tester.pumpAndSettle();
    expect(find.text('Add a phone number'), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-phone')), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-code')), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Authenticator app'),
      findsNothing,
    );
    expect(
      find.byKey(const Key('firebase-mfa-add-phone')),
      findsNothing,
    );
    expect(addPhone, 0);
    expect(sessions, 0);

    await tester.enterText(
      find.byKey(const Key('firebase-mfa-phone')),
      '6505550100',
    );
    await tester.tap(find.byKey(const Key('firebase-mfa-phone-continue')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-mfa-phone')), findsNothing);
    expect(find.byKey(const Key('firebase-mfa-code')), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Authenticator app'),
      findsNothing,
    );

    await tester.enterText(find.byKey(const Key('firebase-mfa-code')), '654321');
    await tester.tap(find.byKey(const Key('firebase-mfa-submit')));
    await tester.pumpAndSettle();
    expect(addPhone, 1);
    expect(enrolledPhone, '+16505550100');
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

  testWidgets('adding an authenticator shows the code and can be skipped', (
    tester,
  ) async {
    var cleared = 0;
    final client = MockClient((request) async {
      if (request.url.path.contains('mfaEnrollment:start')) {
        return http.Response(
          jsonEncode({
            'totpSessionInfo': {
              'sessionInfo': 'session-1',
              'sharedSecretKey': 'SECRETKEY',
            },
          }),
          200,
        );
      }
      return http.Response('no', 404);
    });
    await tester.pumpWidget(
      _gateHost(
        active: false,
        addAuthenticator: true,
        client: client,
        onCleared: () => cleared += 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add an authenticator app'), findsWidgets);
    expect(find.byKey(const Key('settings-totp-secret')), findsOneWidget);
    expect(find.byKey(const Key('settings-phone')), findsNothing);
    expect(find.byKey(const Key('library')), findsNothing);

    await tester.tap(find.byKey(const Key('firebase-mfa-gate-skip')));
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });

  testWidgets('adding a phone number can be skipped', (tester) async {
    var cleared = 0;
    await tester.pumpWidget(
      _gateHost(
        active: false,
        addPhone: true,
        client: MockClient((_) async => http.Response('no', 404)),
        onCleared: () => cleared += 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add a phone number'), findsOneWidget);
    expect(find.byKey(const Key('settings-phone')), findsOneWidget);
    expect(find.byKey(const Key('settings-add-totp')), findsNothing);
    expect(find.byKey(const Key('firebase-mfa-gate-skip')), findsOneWidget);
    expect(cleared, 0);

    await tester.tap(find.byKey(const Key('firebase-mfa-gate-skip')));
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });

  testWidgets('authenticator setup asks to scan once, then for the code', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.contains('mfaEnrollment:start')) {
        return http.Response(
          jsonEncode({
            'totpSessionInfo': {
              'sessionInfo': 'session-1',
              'sharedSecretKey': 'SECRETKEY',
            },
          }),
          200,
        );
      }
      return http.Response('no', 404);
    });
    await tester.pumpWidget(
      _gateHost(active: false, addAuthenticator: true, client: client),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-totp-secret')), findsOneWidget);
    expect(find.text('SECRETKEY'), findsOneWidget);
    expect(find.byKey(const Key('settings-totp-next')), findsOneWidget);
    expect(find.byKey(const Key('settings-totp-code')), findsNothing);
    expect(find.textContaining('Do not scan this code again.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-totp-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-totp-code')), findsOneWidget);
    expect(find.byKey(const Key('settings-totp-secret')), findsNothing);
    expect(find.textContaining('6-digit code'), findsOneWidget);

    await tester.tap(find.byKey(const Key('firebase-mfa-gate-back')));
    await tester.pumpAndSettle();
    expect(find.text('SECRETKEY'), findsOneWidget);
    expect(find.byKey(const Key('settings-totp-code')), findsNothing);
    expect(find.byKey(const Key('settings-totp-next')), findsOneWidget);
  });

  testWidgets('each gate step has its own title, Verify, and no Sign out', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.contains('accounts:lookup')) {
        return http.Response(jsonEncode({'users': <Object>[]}), 200);
      }
      if (request.url.path.contains('mfaEnrollment:start')) {
        return http.Response(
          jsonEncode({
            'totpSessionInfo': {
              'sessionInfo': 'session-1',
              'sharedSecretKey': 'SECRETKEY',
            },
          }),
          200,
        );
      }
      return http.Response('no', 404);
    });
    await tester.pumpWidget(
      _gateHost(
        active: true,
        newAccount: true,
        prefs: const DesktopPrefs(requireSecondFactor: false),
        client: client,
      ),
    );
    await tester.pumpAndSettle();

    // Choice page keeps the account title, Continue, and Sign out.
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-gate-sign-out')), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-gate-skip-new')), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-gate-back')), findsNothing);

    await tester.tap(find.byKey(const Key('settings-add-totp')));
    await tester.pumpAndSettle();
    expect(find.text('Scan this code'), findsOneWidget);
    expect(find.text('Create your account'), findsNothing);
    expect(find.byKey(const Key('firebase-mfa-gate-sign-out')), findsNothing);
    expect(find.byKey(const Key('firebase-mfa-gate-skip-new')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('firebase-mfa-gate-back')),
        matching: find.byType(Text),
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is OutlinedButton && w.key == const Key('firebase-mfa-gate-back'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('settings-totp-next')));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Add authenticator'), findsNothing);
    expect(find.byKey(const Key('firebase-mfa-gate-sign-out')), findsNothing);
    expect(find.byKey(const Key('firebase-mfa-gate-skip-new')), findsNothing);

    // Back returns to the QR, then to the choice page.
    await tester.tap(find.byKey(const Key('firebase-mfa-gate-back')));
    await tester.pumpAndSettle();
    expect(find.text('Scan this code'), findsOneWidget);
    await tester.tap(find.byKey(const Key('firebase-mfa-gate-back')));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-gate-sign-out')), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-gate-skip-new')), findsOneWidget);
  });

  testWidgets('the text code step is titled Enter the code', (tester) async {
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
    expect(find.text('Enter the code'), findsOneWidget);
    expect(find.text('Verify'), findsOneWidget);
    expect(find.text('Add phone'), findsNothing);
    expect(find.byKey(const Key('firebase-mfa-gate-sign-out')), findsNothing);
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

  test('password sign-up is a new account even without isNewUser', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/v1/accounts:signUp');
      return http.Response(jsonEncode(_identityBody()), 200);
    });
    final session = await signInWithPassword(
      config: _publicConfig,
      email: 'a@example.com',
      password: 'secret',
      signUp: true,
      httpClient: client,
    );
    expect(session.isNewUser, isTrue);
  });

  test('google sign-in keeps isNewUser from Firebase', () async {
    final client = MockClient((request) async {
      if (request.url.path == '/auth/google/token') {
        return http.Response(jsonEncode({'idToken': 'google-id'}), 200);
      }
      expect(request.url.path, '/v1/accounts:signInWithIdp');
      return http.Response(jsonEncode(_identityBody(isNewUser: true)), 200);
    });
    final session = await signInWithGoogleCode(
      config: _publicConfig,
      apiUrl: 'http://localhost:8787',
      code: 'code-1',
      codeVerifier: 'verifier',
      redirectUri: 'http://127.0.0.1:9/callback',
      httpClient: client,
    );
    expect(session.isNewUser, isTrue);
  });

  test('an emailed code for a new user is a sign-up', () async {
    final client = MockClient((request) async {
      return http.Response(jsonEncode(_identityBody(isNewUser: true)), 200);
    });
    final session = await signInWithEmailLink(
      config: _publicConfig,
      email: 'a@example.com',
      oobCode: 'oob-1',
      httpClient: client,
    );
    expect(session.isNewUser, isTrue);
  });

  test('password sign-in EMAIL_NOT_FOUND is a missing account', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'EMAIL_NOT_FOUND'},
        }),
        400,
      );
    });
    await expectLater(
      signInWithPassword(
        config: _publicConfig,
        email: 'a@example.com',
        password: 'secret',
        signUp: false,
        httpClient: client,
      ),
      throwsA(isA<FirebaseAccountMissing>()),
    );
  });

  test(
    'refresh maps a deleted user to revoked and a 500 to a plain failure',
    () async {
      Future<void> expectRevoked(String code) async {
        final client = MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {'message': code},
            }),
            400,
          );
        });
        await expectLater(
          refreshFirebaseSession(
            config: _publicConfig,
            refreshToken: 'refresh-1',
            httpClient: client,
          ),
          throwsA(isA<FirebaseSessionRevoked>()),
        );
      }

      await expectRevoked('USER_NOT_FOUND');
      await expectRevoked('TOKEN_EXPIRED');

      final server = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': {'message': 'USER_NOT_FOUND'},
          }),
          500,
        );
      });
      await expectLater(
        refreshFirebaseSession(
          config: _publicConfig,
          refreshToken: 'refresh-1',
          httpClient: server,
        ),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error is FirebaseSessionRevoked,
            'revoked',
            isFalse,
          ),
        ),
      );

      final offline = MockClient((request) async {
        throw http.ClientException('offline');
      });
      await expectLater(
        refreshFirebaseSession(
          config: _publicConfig,
          refreshToken: 'refresh-1',
          httpClient: offline,
        ),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error is FirebaseSessionRevoked,
            'revoked',
            isFalse,
          ),
        ),
      );
    },
  );

  testWidgets('password EMAIL_NOT_FOUND switches to Create account', (
    tester,
  ) async {
    var sessions = 0;
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': {'message': 'EMAIL_NOT_FOUND'},
        }),
        400,
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: FirebaseSignInPage(
          config: _publicConfig,
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
    await tester.tap(find.byKey(const Key('firebase-use-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('firebase-submit')));
    await tester.pumpAndSettle();
    expect(sessions, 0);
    expect(find.text('Create account'), findsWidgets);
    expect(
      find.text('No account for that email. Create one below.'),
      findsOneWidget,
    );
  });

  testWidgets('a new account shows Create your account and no Continue', (
    tester,
  ) async {
    final store = await _pumpShell(
      tester,
      client: _shellClient(
        onIdentity: (request) async {
          if (request.url.path.contains('accounts:signUp')) {
            return http.Response(jsonEncode(_identityBody()), 200);
          }
          return http.Response('missing', 404);
        },
      ),
    );
    await _createAccount(tester);
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Add a second factor'), findsNothing);
    expect(find.byKey(const Key('firebase-mfa-gate-skip-new')), findsNothing);
    expect(await store.read(key: kFirebaseGateKey), kFirebaseGateNew);
  });

  testWidgets('a new account can continue when a second factor is optional', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      library: true,
      prefs: const DesktopPrefs(requireSecondFactor: false),
      client: _shellClient(
        onIdentity: (request) async {
          if (request.url.path.contains('accounts:signUp')) {
            return http.Response(jsonEncode(_identityBody()), 200);
          }
          return http.Response('missing', 404);
        },
      ),
    );
    await _createAccount(tester);
    expect(find.byKey(const Key('firebase-mfa-gate-skip-new')), findsOneWidget);
    await tester.tap(find.byKey(const Key('firebase-mfa-gate-skip-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('signed-in-home')), findsOneWidget);
    expect(find.byKey(const Key('firebase-mfa-gate')), findsNothing);
  });

  testWidgets('an emailed code for a new user shows Create your account', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      client: _shellClient(
        onIdentity: (request) async {
          if (request.url.path == '/auth/email-code') {
            return http.Response(
              jsonEncode({'emailMasked': 'a...@example.com'}),
              200,
            );
          }
          if (request.url.path == '/auth/email-code/verify') {
            return http.Response(jsonEncode({'oobCode': 'oob-1'}), 200);
          }
          if (request.url.path.contains('signInWithEmailLink')) {
            return http.Response(
              jsonEncode(_identityBody(isNewUser: true)),
              200,
            );
          }
          return http.Response('missing', 404);
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key('firebase-email')),
      'a@example.com',
    );
    await tester.tap(find.byKey(const Key('firebase-email-me')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-email-code')),
      '123456',
    );
    await tester.tap(find.byKey(const Key('firebase-email-code-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('No account for that email.'), findsNothing);
    expect(find.byKey(const Key('firebase-auth-error')), findsNothing);
  });

  testWidgets('an existing sign-in still shows Add a second factor', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      client: _shellClient(
        onIdentity: (request) async {
          if (request.url.path.contains('signInWithPassword')) {
            return http.Response(jsonEncode(_identityBody()), 200);
          }
          return http.Response('missing', 404);
        },
      ),
    );
    await tester.enterText(
      find.byKey(const Key('firebase-email')),
      'a@example.com',
    );
    await tester.tap(find.byKey(const Key('firebase-use-password')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('firebase-password')),
      'secret',
    );
    await tester.tap(find.byKey(const Key('firebase-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Add a second factor'), findsOneWidget);
    expect(find.text('Create your account'), findsNothing);
  });

  testWidgets('verifying email does not leave the new-account step', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      client: _shellClient(
        onIdentity: (request) async {
          final path = request.url.path;
          if (path.contains('accounts:signUp')) {
            return http.Response(jsonEncode(_identityBody()), 200);
          }
          if (path == '/auth/email-code') {
            return http.Response(
              jsonEncode({'emailMasked': 'a...@example.com'}),
              200,
            );
          }
          if (path == '/auth/email-code/verify') {
            return http.Response(jsonEncode({'oobCode': 'oob-1'}), 200);
          }
          if (path.contains('signInWithEmailLink')) {
            return http.Response(
              jsonEncode(_identityBody(idToken: _verifiedToken())),
              200,
            );
          }
          return http.Response('missing', 404);
        },
      ),
    );
    await _createAccount(tester);
    expect(find.text('Create your account'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings-verify-email')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      '123456',
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Continue'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('settings-verify-email')), findsNothing);
  });

  testWidgets(
    'an existing sign-in with the setting off writes no gate marker',
    (tester) async {
      final store = await _pumpShell(
        tester,
        library: true,
        prefs: const DesktopPrefs(requireSecondFactor: false),
        client: _shellClient(
          onIdentity: (request) async {
            if (request.url.path.contains('signInWithPassword')) {
              return http.Response(jsonEncode(_identityBody()), 200);
            }
            return http.Response('missing', 404);
          },
        ),
      );
      await tester.enterText(
        find.byKey(const Key('firebase-email')),
        'a@example.com',
      );
      await tester.tap(find.byKey(const Key('firebase-use-password')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('firebase-password')),
        'secret',
      );
      await tester.tap(find.byKey(const Key('firebase-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signed-in-home')), findsOneWidget);
      expect(find.byKey(const Key('firebase-mfa-gate')), findsNothing);
      expect(await store.read(key: kFirebaseGateKey), isNull);
    },
  );

  testWidgets('a stored new-account marker resumes Create your account', (
    tester,
  ) async {
    final store = MemorySecureKeyValueStore();
    await _writeStoredSession(store, marker: kFirebaseGateNew);
    await _pumpShell(
      tester,
      store: store,
      client: _shellClient(onIdentity: _unusedIdentity),
    );
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byKey(const Key('signed-in-home')), findsNothing);
  });

  testWidgets('a stored require marker resumes Add a second factor', (
    tester,
  ) async {
    final store = MemorySecureKeyValueStore();
    await _writeStoredSession(store, marker: kFirebaseGateRequire);
    await _pumpShell(
      tester,
      store: store,
      client: _shellClient(onIdentity: _unusedIdentity),
    );
    expect(find.text('Add a second factor'), findsOneWidget);
    expect(find.text('Create your account'), findsNothing);
  });

  testWidgets('finishing the gate deletes the marker', (tester) async {
    final store = MemorySecureKeyValueStore();
    await _writeStoredSession(store, marker: kFirebaseGateRequire);
    await _pumpShell(
      tester,
      store: store,
      library: true,
      client: _shellClient(factors: true, onIdentity: _unusedIdentity),
    );
    expect(find.byKey(const Key('signed-in-home')), findsOneWidget);
    expect(await store.read(key: kFirebaseGateKey), isNull);
  });

  testWidgets('sign out reaches sign-in when Keychain delete fails', (
    tester,
  ) async {
    final store = _ThrowingDeleteStore();
    await _writeStoredSession(store, marker: kFirebaseGateNew);
    await _pumpShell(
      tester,
      store: store,
      client: _shellClient(onIdentity: _unusedIdentity),
    );
    expect(find.text('Create your account'), findsOneWidget);
    Object? asyncError;
    await runZonedGuarded(() async {
      await tester.tap(find.byKey(const Key('firebase-mfa-gate-sign-out')));
      await tester.pump();
      await tester.pumpAndSettle();
    }, (error, stack) {
      asyncError = error;
    });
    expect(asyncError, isA<PlatformException>());
    expect(find.byKey(const Key('firebase-sign-in')), findsOneWidget);
    expect(await store.read(key: kFirebaseSessionKey), isNotNull);
  });

  testWidgets('sign out deletes the gate marker', (tester) async {
    final store = MemorySecureKeyValueStore();
    await _writeStoredSession(store, marker: kFirebaseGateNew);
    await _pumpShell(
      tester,
      store: store,
      client: _shellClient(onIdentity: _unusedIdentity),
    );
    await tester.tap(find.byKey(const Key('firebase-mfa-gate-sign-out')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('firebase-sign-in')), findsOneWidget);
    expect(await store.read(key: kFirebaseGateKey), isNull);
    expect(await store.read(key: kFirebaseSessionKey), isNull);
  });

  testWidgets('a removed account returns to sign-in with a notice', (
    tester,
  ) async {
    final store = MemorySecureKeyValueStore();
    await _writeStoredSession(store, marker: kFirebaseGateNew);
    await _pumpShell(
      tester,
      store: store,
      client: _shellClient(
        tokenStatus: 400,
        tokenCode: 'USER_NOT_FOUND',
        onIdentity: _unusedIdentity,
      ),
    );
    expect(find.byKey(const Key('firebase-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('firebase-sign-in-notice')), findsOneWidget);
    expect(find.text(kAccountRemovedNotice), findsOneWidget);
    expect(await store.read(key: kFirebaseSessionKey), isNull);
    expect(await store.read(key: kFirebaseGateKey), isNull);
  });

  testWidgets(
    'a failed startup refresh keeps the session and opens the library',
    (tester) async {
      final store = MemorySecureKeyValueStore();
      await _writeStoredSession(store);
      await _pumpShell(
        tester,
        store: store,
        library: true,
        client: _shellClient(tokenStatus: 500, onIdentity: _unusedIdentity),
      );
      expect(find.byKey(const Key('signed-in-home')), findsOneWidget);
      expect(find.byKey(const Key('firebase-sign-in-notice')), findsNothing);
      expect(await store.read(key: kFirebaseSessionKey), isNotNull);
    },
  );

  testWidgets('a revoked refresh while signed in signs out', (tester) async {
    final store = MemorySecureKeyValueStore();
    await _writeStoredSession(store);
    await _pumpShell(
      tester,
      store: store,
      library: true,
      client: _shellClient(
        tokenExpiresIn: '1',
        revokeOnSecondToken: true,
        onIdentity: _unusedIdentity,
      ),
    );
    expect(find.byKey(const Key('firebase-sign-in')), findsOneWidget);
    expect(find.byKey(const Key('auth-unauthorized')), findsNothing);
    expect(find.text(kAccountRemovedNotice), findsOneWidget);
    expect(await store.read(key: kFirebaseSessionKey), isNull);
  });
}

Widget _gateHost({
  required bool active,
  required http.Client client,
  bool addAuthenticator = false,
  bool addPhone = false,
  bool newAccount = false,
  DesktopPrefs? prefs,
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
      if (prefs != null) desktopPrefsProvider.overrideWithValue(prefs),
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
        newAccount: newAccount,
        addAuthenticator: addAuthenticator,
        addPhone: addPhone,
        httpClient: client,
        onCleared: onCleared ?? () {},
        child: const Text('library', key: Key('library')),
      ),
    ),
  );
}

const _publicConfig = FirebasePublicConfig(
  apiKey: 'public-key',
  authDomain: 'app.firebaseapp.com',
  projectId: 'app',
);

Map<String, Object?> _identityBody({
  bool isNewUser = false,
  String idToken = 'id-1',
  String expiresIn = '3600',
}) {
  return {
    'idToken': idToken,
    'refreshToken': 'refresh-1',
    'expiresIn': expiresIn,
    'localId': 'uid-1',
    'email': 'a@example.com',
    'isNewUser': isNewUser,
  };
}

Future<http.Response> _unusedIdentity(http.Request request) async {
  return http.Response(
    jsonEncode({
      'error': {'message': 'UNUSED'},
    }),
    404,
  );
}

http.Client _shellClient({
  required Future<http.Response> Function(http.Request request) onIdentity,
  bool factors = false,
  int tokenStatus = 200,
  String? tokenCode,
  String tokenExpiresIn = '3600',
  bool revokeOnSecondToken = false,
}) {
  var tokenCalls = 0;
  return MockClient((request) async {
    final path = request.url.path;
    if (path.contains('accounts:lookup')) {
      if (!factors) {
        return http.Response(jsonEncode({'users': <Object>[]}), 200);
      }
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
    if (request.url.host.contains('securetoken')) {
      tokenCalls += 1;
      if (revokeOnSecondToken && tokenCalls > 1) {
        return http.Response(
          jsonEncode({
            'error': {'message': 'USER_NOT_FOUND'},
          }),
          400,
        );
      }
      if (tokenStatus != 200) {
        return http.Response(
          jsonEncode({
            'error': {'message': tokenCode ?? 'BACKEND'},
          }),
          tokenStatus,
        );
      }
      return http.Response(
        jsonEncode({
          'id_token': 'id-2',
          'refresh_token': 'refresh-2',
          'expires_in': tokenExpiresIn,
          'user_id': 'uid-1',
        }),
        200,
      );
    }
    if (path == '/me') {
      return http.Response(
        jsonEncode({
          'id': 'acc_1',
          'email': 'a@example.com',
          'createdAt': '2026-07-18T00:00:00.000Z',
        }),
        200,
      );
    }
    return onIdentity(request);
  });
}

Future<SecureKeyValueStore> _pumpShell(
  WidgetTester tester, {
  required http.Client client,
  SecureKeyValueStore? store,
  DesktopPrefs? prefs,
  bool library = false,
}) async {
  final memory = store ?? MemorySecureKeyValueStore();
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
              firebase: _publicConfig,
            ),
          ),
        ),
        authHttpClientProvider.overrideWithValue(client),
        securePersistorProvider.overrideWithValue(
          SecureStoragePersistor(store: memory),
        ),
        if (prefs != null) desktopPrefsProvider.overrideWithValue(prefs),
        if (library) ...[
          itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
          commentsRepositoryProvider.overrideWithValue(
            FakeCommentsRepository(),
          ),
          personsRepositoryProvider.overrideWithValue(FakePersonsRepository()),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          jobsRepositoryProvider.overrideWithValue(FakeJobsRepository()),
          collectionsStoreProvider.overrideWithValue(MemoryCollectionsStore()),
        ],
      ],
      child: const MaterialApp(
        home: AuthShell(
          signedInHome: Text('library', key: Key('signed-in-home')),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return memory;
}

Future<void> _createAccount(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('firebase-toggle-mode')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('firebase-email')),
    'a@example.com',
  );
  await tester.enterText(find.byKey(const Key('firebase-password')), 'secret');
  await tester.tap(find.byKey(const Key('firebase-submit')));
  await tester.pumpAndSettle();
}

Future<void> _writeStoredSession(
  SecureKeyValueStore store, {
  String? marker,
}) async {
  final session = FirebaseSession(
    idToken: 'id-1',
    refreshToken: 'refresh-1',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    localId: 'uid-1',
    email: 'a@example.com',
  );
  await store.write(
    key: kFirebaseSessionKey,
    value: jsonEncode(session.toJson()),
  );
  if (marker != null) {
    await store.write(key: kFirebaseGateKey, value: marker);
  }
}

/// Delete always fails. Read and write keep the entry, as a Keychain
/// failure that did not remove the saved sign-in would.
class _ThrowingDeleteStore extends MemorySecureKeyValueStore {
  @override
  Future<void> delete({required String key}) async {
    throw PlatformException(
      code: 'Unexpected security result code',
      message: 'Code: -1, Message: denied',
    );
  }
}

/// Firebase accepts only a top-level enrollment id and a code object whose
/// single key is verificationCode. Anything else is the invalid-argument error.
http.Response _totpFinalizeResponse(http.Request request, {String? code}) {
  final body = jsonDecode(request.body) as Map<String, dynamic>;
  final totp = body['totpVerificationInfo'];
  final keys = totp is Map ? totp.keys.map((key) => '$key').toSet() : <String>{};
  final enrollmentId = body['mfaEnrollmentId'];
  if (enrollmentId is! String ||
      enrollmentId.isEmpty ||
      keys.length != 1 ||
      !keys.contains('verificationCode')) {
    return http.Response(
      jsonEncode({
        'error': {'message': 'Request contains an invalid argument.'},
      }),
      400,
    );
  }
  if (code != null && totp['verificationCode'] != code) {
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

String _verifiedToken() {
  String part(Object value) {
    return base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  }

  return '${part({'alg': 'none'})}.${part({'email_verified': true})}.x';
}
