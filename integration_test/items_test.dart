// D2 Library & Item Registry integration: list → detail against a fake
// ItemsRepository (mocked API per §5; no live network).
//   flutter test integration_test/items_test.dart -d macos   (or -d windows)

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/main.dart';

import '../test/fake_items_repository.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('items list renders and opens detail on the desktop host',
      (WidgetTester tester) async {
    final item = fixtureItem(
      id: 'item_int',
      processingStatus: ProcessingStatus.tagged,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          testSessionProvider.overrideWithValue(
            const TestSession(
              token: 'integration-token',
              account: Account(
                id: 'acc_integration',
                email: 'integration@example.com',
                createdAt: '2026-07-18T00:00:00.000Z',
              ),
            ),
          ),
          itemsRepositoryProvider.overrideWithValue(
            FakeItemsRepository(items: [item]),
          ),
        ],
        child: const TagKinDesktopApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('items-list')), findsOneWidget);
    expect(find.byKey(const Key('item-row-item_int')), findsOneWidget);
    expect(find.byKey(const Key('processing-status-tagged')), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-row-item_int')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('item-detail')), findsOneWidget);
    expect(find.byKey(const Key('item-id')), findsOneWidget);
  });
}
