import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/auth/macos_oauth_return_hint.dart';

void main() {
  testWidgets('waiting copy names Allow, not the callback URL', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MacOsOauthReturnHint(),
        ),
      ),
    );

    expect(find.byKey(const Key('oauth-browser-wait')), findsOneWidget);
    expect(find.textContaining('Allow'), findsOneWidget);
    expect(find.textContaining(kTagkinOauthCallbackUri), findsNothing);
    expect(find.byKey(const Key('oauth-browser-timeout')), findsNothing);
    expect(find.byKey(const Key('oauth-browser-retry')), findsNothing);
  });

  testWidgets('timeout offers Try again without Clerk URL', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MacOsOauthReturnHint(
            timedOut: true,
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('oauth-browser-timeout')), findsOneWidget);
    expect(find.textContaining('Sign-in didn’t finish.'), findsOneWidget);
    expect(find.textContaining('Quit TagKin'), findsNothing);
    expect(find.textContaining(kTagkinOauthCallbackUri), findsNothing);
    expect(find.byKey(const Key('oauth-browser-wait')), findsNothing);

    await tester.tap(find.byKey(const Key('oauth-browser-retry')));
    expect(retries, 1);
  });

  testWidgets('second miss tells the user to quit and reopen', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MacOsOauthReturnHint(
            timedOut: true,
            repeatMiss: true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('oauth-browser-timeout')), findsOneWidget);
    expect(find.textContaining('Quit TagKin and open it again'), findsOneWidget);
    expect(find.byKey(const Key('oauth-browser-retry')), findsOneWidget);
    expect(find.textContaining(kTagkinOauthCallbackUri), findsNothing);
  });
}
