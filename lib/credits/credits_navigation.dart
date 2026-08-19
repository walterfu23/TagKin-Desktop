import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/credits/buy_credits_page.dart';
import 'package:tagkin_desktop/credits/redeem_code_page.dart';
import 'package:tagkin_desktop/credits/trial_card_page.dart';

/// Push [BuyCreditsPage] on the nearest navigator, preserving [ProviderScope].
Future<void> pushBuyCreditsPage(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'buy-credits'),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const BuyCreditsPage(),
      ),
    ),
  );
}

/// Push [RedeemCodePage] on the nearest navigator, preserving [ProviderScope].
Future<void> pushRedeemCodePage(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'redeem-code'),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const RedeemCodePage(),
      ),
    ),
  );
}

/// Push [TrialCardPage] on the nearest navigator, preserving [ProviderScope].
Future<void> pushTrialCardPage(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'trial-card'),
      builder: (_) => UncontrolledProviderScope(
        container: container,
        child: const TrialCardPage(),
      ),
    ),
  );
}
