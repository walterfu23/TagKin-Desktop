import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/buy_credits_page.dart';
import 'package:tagkin_desktop/credits/credits_navigation.dart';
import 'package:tagkin_desktop/credits/redeem_code_page.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

import 'fake_credits_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  testWidgets('Redeem opens a debt dialog then confirm applies',
      (tester) async {
    final credits = FakeCreditsRepository(
      preview: const RedeemPreview(
        packId: 'pack20',
        credits: 2000,
        debtCreditsToClear: 1200,
        netCredits: 800,
        expiresAt: '2099-01-01T00:00:00.000Z',
      ),
      redeemResult: const RedeemResult(
        packId: 'pack20',
        credits: 2000,
        debtPaidCredits: 1200,
        netCredits: 800,
        remainingCredits: 800,
        creditDebt: 0,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsRepositoryProvider.overrideWithValue(credits),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
        ],
        child: const MaterialApp(
          home: SelectableScope(child: RedeemCodePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('You have 10,000 credits.'), findsOneWidget);

    final redeemBefore = tester.widget<FilledButton>(
      find.byKey(const Key('redeem-code-redeem')),
    );
    expect(redeemBefore.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('redeem-code-input')),
      'TK-ABCD-EFGH-JKLM',
    );
    await tester.pump();

    expect(find.byKey(const Key('redeem-code-confirm')), findsNothing);
    await tester.tap(find.byKey(const Key('redeem-code-redeem')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Redeem this code?'), findsOneWidget);
    expect(
      find.text(
        '1,200 credits will clear refund debt; 800 will be added.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('redeem-code-confirm')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('redeem-code-applied')), findsOneWidget);
    expect(find.text('Credits applied. Remaining: 800.'), findsOneWidget);
  });

  testWidgets('invalid preview surfaces the server reject message',
      (tester) async {
    final credits = FakeCreditsRepository(
      previewError: ApiException(
        statusCode: 409,
        code: 'redeemCodeInvalid',
        message: 'That code is not valid.',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsRepositoryProvider.overrideWithValue(credits),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
        ],
        child: const MaterialApp(
          home: SelectableScope(child: RedeemCodePage()),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('redeem-code-input')),
      'nope',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('redeem-code-redeem')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('redeem-code-error')), findsOneWidget);
    expect(find.text('That code is not valid.'), findsOneWidget);
    expect(find.text('Redeem this code?'), findsNothing);
  });

  testWidgets('Add credits page has a separate Redeem code section',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsRepositoryProvider.overrideWithValue(FakeCreditsRepository()),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          checkoutUrlLauncherProvider.overrideWithValue((uri) async => true),
        ],
        child: const MaterialApp(
          home: SelectableScope(child: BuyCreditsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Add credits'), findsOneWidget);
    expect(find.text('Have a redeem code?'), findsOneWidget);
    expect(find.text('Use a code instead of buying a pack.'), findsOneWidget);
    expect(find.byKey(const Key('buy-credits-have-a-code')), findsOneWidget);
    expect(
      tester.widget<FilledButton>(
        find.byKey(const Key('buy-credits-have-a-code')),
      ),
      isA<FilledButton>(),
    );
    expect(find.text('Redeem code'), findsOneWidget);
  });

  testWidgets('redeeming from Add credits returns to the page underneath',
      (tester) async {
    final credits = FakeCreditsRepository(
      preview: const RedeemPreview(
        packId: 'pack20',
        credits: 2000,
        debtCreditsToClear: 0,
        netCredits: 2000,
        expiresAt: '2099-01-01T00:00:00.000Z',
      ),
      redeemResult: const RedeemResult(
        packId: 'pack20',
        credits: 2000,
        debtPaidCredits: 0,
        netCredits: 2000,
        remainingCredits: 12000,
        creditDebt: 0,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsRepositoryProvider.overrideWithValue(credits),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          checkoutUrlLauncherProvider.overrideWithValue((uri) async => true),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => pushBuyCreditsPage(context),
                child: const Text('Library'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('Add credits'), findsOneWidget);

    await tester.tap(find.byKey(const Key('buy-credits-have-a-code')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('redeem-code-input')),
      'TK-ABCD-EFGH-JKLM',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('redeem-code-redeem')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('redeem-code-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Add credits'), findsNothing);
    expect(find.text('Redeem code'), findsNothing);
  });
}
