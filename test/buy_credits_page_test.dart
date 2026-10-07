import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/buy_credits_page.dart';
import 'package:tagkin_desktop/credits/checkout_launcher.dart';
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

    expect(find.text('You have 10,000 credits.'), findsOneWidget);
    expect(find.text('\$20 — 2,000 credits'), findsOneWidget);
    expect(
      find.text(
        '1,200 credits will clear refund debt; 800 will be added.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('buy-credits-checkout')));
    await tester.pump();
    await tester.pump();
    expect(launched, [Uri.parse('https://checkout.stripe.com/c/pay/cs_test_1')]);
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
    expect(find.text('You have 0 credits.'), findsOneWidget);
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
    expect(find.text('Credits applied. Remaining: 2,000.'), findsOneWidget);
    expect(usage.getUsageCallCount, greaterThan(0));
  });

  testWidgets('insufficient and out-of-credits banners offer Add credits',
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
    expect(find.text('Add credits'), findsOneWidget);

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
    expect(find.text('Add credits'), findsOneWidget);
  });

  testWidgets('Free trial section follows pack availability and grant',
      (tester) async {
    Future<void> pump(TrialSummary summary) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            creditsRepositoryProvider.overrideWithValue(
              FakeCreditsRepository(trial: summary),
            ),
            usageRepositoryProvider.overrideWithValue(FakeUsageRepository()),
            checkoutUrlLauncherProvider.overrideWithValue((uri) async => true),
          ],
          child: const MaterialApp(
            home: SelectableScope(child: BuyCreditsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    TrialSummary summary({
      TrialStatus status = TrialStatus.notstarted,
      bool available = true,
    }) {
      return TrialSummary(
        status: status,
        eligible: status != TrialStatus.granted,
        available: available,
        neverHadCredits: false,
        publishableKey: 'pk_test_stub',
      );
    }

    await pump(summary());
    expect(find.byKey(const Key('buy-credits-free-trial')), findsOneWidget);
    await tester.tap(find.byKey(const Key('buy-credits-free-trial')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trial-card-heading')), findsOneWidget);
    expect(find.text('Get your free credits'), findsOneWidget);
    expect(find.text('Free trial'), findsWidgets);

    await pump(summary(status: TrialStatus.granted, available: true));
    expect(find.byKey(const Key('buy-credits-free-trial')), findsNothing);

    await pump(summary(available: false));
    expect(find.byKey(const Key('buy-credits-free-trial')), findsNothing);
  });

  testWidgets('stub checkout host is not opened', (tester) async {
    final credits = FakeCreditsRepository(
      purchase: const CreditPurchaseView(
        purchaseId: 'pur_stub',
        status: CreditPurchaseStatus.pending,
        packId: 'pack20',
        priceUsdCents: 2000,
        currency: 'usd',
        credits: 2000,
        maxDebtCreditsToClear: 0,
        quotedNetCredits: 2000,
        checkoutUrl: 'https://checkout.stripe.test/cs_test_1',
        remainingCredits: 0,
      ),
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
    await tester.tap(find.byKey(const Key('buy-credits-checkout')));
    await tester.pump();
    await tester.pump();

    expect(launched, isEmpty);
    expect(find.text(stubCheckoutMessage), findsOneWidget);
  });

  testWidgets('Open card form does not open the stub host', (tester) async {
    final credits = FakeCreditsRepository(
      trial: const TrialSummary(
        status: TrialStatus.notstarted,
        eligible: true,
        available: true,
        neverHadCredits: true,
        publishableKey: 'pk_test_stub',
      ),
      verification: const TrialVerificationCreated(
        verificationId: 'ver_1',
        intentKind: TrialIntentKind.setupintent,
        cardSetupUrl: 'https://checkout.stripe.test/cs_setup',
        publishableKey: 'pk_test_stub',
      ),
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
    await tester.tap(find.byKey(const Key('buy-credits-free-trial')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trial-card-open')));
    await tester.pump();
    await tester.pump();

    expect(launched, isEmpty);
    expect(find.text(stubCheckoutMessage), findsOneWidget);
  });
}
