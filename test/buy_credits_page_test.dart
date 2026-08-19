import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/buy_credits_page.dart';
import 'package:tagkin_desktop/usage/usage_banner.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

import 'fake_credits_repository.dart';
import 'fake_usage_repository.dart';

void main() {
  testWidgets('renders server pack sticker and net-credit disclosure',
      (tester) async {
    final credits = FakeCreditsRepository(
      packs: const [
        CreditPackOffer(
          packId: 'pack20',
          priceUsdCents: 2000,
          credits: 2000,
          debtCreditsToClear: 1200,
          netCredits: 800,
        ),
      ],
    );
    final launched = <Uri>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsRepositoryProvider.overrideWithValue(credits),
          usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
          checkoutUrlLauncherProvider.overrideWithValue((uri) async {
            launched.add(uri);
            return true;
          }),
        ],
        child: const MaterialApp(
          home: SelectableScope(child: BuyCreditsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('\$20 — 2,000 credits'), findsOneWidget);
    expect(
      find.text(
        '1,200 credits will clear refund debt; 800 will become remaining.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('buy-credits-checkout')));
    await tester.pump();
    await tester.pump();
    expect(launched, [Uri.parse('https://checkout.stripe.test/cs_test_1')]);
    expect(launched.single.toString(), isNot(contains('Bearer')));
    expect(launched.single.toString(), isNot(contains('sk_')));
  });

  testWidgets('I finished in the browser stops on paid and refreshes usage',
      (tester) async {
    final credits = FakeCreditsRepository();
    final usage = FakeUsageRepository(
      summary: fixtureUsageSummary(
        creditAdmission: true,
        remainingCredits: 0,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          creditsRepositoryProvider.overrideWithValue(credits),
          usageRepositoryProvider.overrideWithValue(usage),
          checkoutUrlLauncherProvider.overrideWithValue((uri) async => true),
        ],
        child: const MaterialApp(
          home: SelectableScope(child: BuyCreditsPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('buy-credits-checkout')));
    await tester.pump();
    await tester.pump();

    credits.purchase = const CreditPurchaseView(
      purchaseId: 'pur_1',
      status: CreditPurchaseStatus.paid,
      packId: 'pack20',
      priceUsdCents: 2000,
      currency: 'usd',
      credits: 2000,
      maxDebtCreditsToClear: 0,
      quotedNetCredits: 2000,
      remainingCredits: 2000,
    );
    usage.summary = fixtureUsageSummary(
      creditAdmission: true,
      remainingCredits: 2000,
    );

    await tester.tap(find.byKey(const Key('buy-credits-finished')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('buy-credits-applied')), findsOneWidget);
    expect(usage.getUsageCallCount, greaterThan(0));
  });

  testWidgets('insufficient and out-of-credits banners offer Buy credits',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageBanner(
            gate: UsageGate.fromSummary(
              fixtureUsageSummary(
                creditAdmission: true,
                remainingCredits: 0,
              ),
            ),
            onBuyCredits: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('usage-banner-buy-credits')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsageBanner(
            gate: UsageGate.fromSummary(
              fixtureUsageSummary(
                creditAdmission: true,
                remainingCredits: 40,
                lowCreditWarning: true,
              ),
            ),
            analyzeRejectCode: 'insufficientCredits',
            onBuyCredits: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('usage-banner-insufficient-credits')),
        findsOneWidget);
    expect(find.byKey(const Key('usage-banner-buy-credits')), findsOneWidget);
  });
}
