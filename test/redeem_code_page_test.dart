import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/buy_credits_page.dart';
import 'package:tagkin_desktop/credits/redeem_code_page.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

import 'fake_credits_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  testWidgets('preview shows server debt disclosure then redeem applies',
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

    await tester.enterText(
      find.byKey(const Key('redeem-code-input')),
      'TK-ABCD-EFGH-JKLM',
    );
    await tester.pump();

    expect(find.byKey(const Key('redeem-code-confirm')), findsOneWidget);
    final confirmBefore = tester.widget<FilledButton>(
      find.byKey(const Key('redeem-code-confirm')),
    );
    expect(confirmBefore.onPressed, isNull);

    await tester.tap(find.byKey(const Key('redeem-code-preview')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text(
        '1,200 credits will clear refund debt; 800 will become remaining.',
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
    await tester.tap(find.byKey(const Key('redeem-code-preview')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('redeem-code-error')), findsOneWidget);
    expect(find.text('That code is not valid.'), findsOneWidget);
  });

  testWidgets('Buy credits offers Have a code?', (tester) async {
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
    expect(find.byKey(const Key('buy-credits-have-a-code')), findsOneWidget);
    expect(find.text('Have a code?'), findsOneWidget);
  });
}
