import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';

Account _account(String id) => Account(
      id: id,
      email: '$id@example.com',
      createdAt: '2026-07-18T00:00:00.000Z',
    );

void main() {
  testWidgets('valid session populates account and shows foundation home',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            TestSession(token: 'tok', account: _account('acc_1')),
          ),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('foundation-ready')), findsOneWidget);
    expect(find.byKey(const Key('account-label')), findsOneWidget);
    expect(find.text('acc_1@example.com'), findsOneWidget);
  });

  testWidgets('401 on /me surfaces unauthorized — no crash, no retry loop',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            TestSession(
              token: 'expired',
              meError: UnauthorizedException(message: 'Expired'),
            ),
          ),
        ],
        child: const MaterialApp(
          home: AuthShell(
            signedInHome: FoundationHomePage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('auth-unauthorized')), findsOneWidget);
    expect(find.byKey(const Key('foundation-ready')), findsNothing);
  });

  testWidgets('missing Clerk key shows configure prompt (no crash)',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: TagKinDesktopApp()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('missing-clerk-config')), findsOneWidget);
  });
}
