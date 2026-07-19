// D0 foundation smoke: with a fake signed-in session, the app boots to the
// library shell (D2 post-auth home).

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';

import 'fake_items_repository.dart';

void main() {
  testWidgets('app boots to the library shell when signed in',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            TestSession(
              token: 'test-token',
              account: const Account(
                id: 'acc_test',
                email: 'test@example.com',
                createdAt: '2026-07-18T00:00:00.000Z',
              ),
            ),
          ),
          itemsRepositoryProvider.overrideWithValue(FakeItemsRepository()),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-empty')), findsOneWidget);
    expect(find.text(kAppTitle), findsWidgets);
  });
}
