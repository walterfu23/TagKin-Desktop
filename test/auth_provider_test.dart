import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:tagkin_desktop/auth/firebase_sign_in_page.dart';
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

  test('changing the global provider clears the previous local session', () async {
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
  });

  testWidgets('firebase bootstrap shows the firebase sign-in form', (tester) async {
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

  testWidgets('firebase sign-in shows Continue with Google when bootstrap has a client id',
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
  });
}
