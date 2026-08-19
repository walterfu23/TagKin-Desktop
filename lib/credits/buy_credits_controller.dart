import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/credits_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show creditsRepositoryProvider, checkoutUrlLauncherProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/checkout_launcher.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

enum BuyCreditsPhase {
  idle,
  loadingOffers,
  ready,
  creating,
  awaitingBrowser,
  polling,
  applied,
  expired,
  failed,
}

class BuyCreditsController extends ChangeNotifier {
  BuyCreditsController({
    required this.creditsRepository,
    required this.usageController,
    required this.launchUrl,
    this.pollInterval = const Duration(seconds: 3),
    this.pollCap = const Duration(minutes: 10),
  });

  final CreditsRepository creditsRepository;
  final UsageController usageController;
  final CheckoutUrlLauncher launchUrl;
  final Duration pollInterval;
  final Duration pollCap;

  BuyCreditsPhase phase = BuyCreditsPhase.idle;
  List<CreditPackOffer> offers = const [];
  CreditPackOffer? selected;
  CreditPurchaseView? purchase;
  String? errorMessage;
  final List<Uri> launchedUrls = <Uri>[];

  Timer? _poll;
  DateTime? _pollStartedAt;

  Future<void> loadOffers() async {
    phase = BuyCreditsPhase.loadingOffers;
    errorMessage = null;
    notifyListeners();
    try {
      final listed = await creditsRepository.listPacks();
      offers = listed.packs;
      selected = offers.isEmpty ? null : offers.first;
      phase = BuyCreditsPhase.ready;
    } catch (e) {
      errorMessage = e.toString();
      phase = BuyCreditsPhase.failed;
    }
    notifyListeners();
  }

  void select(CreditPackOffer offer) {
    selected = offer;
    notifyListeners();
  }

  Future<void> startCheckout() async {
    final offer = selected;
    if (offer == null) return;
    phase = BuyCreditsPhase.creating;
    errorMessage = null;
    notifyListeners();
    try {
      final created = await creditsRepository.createPurchase(packId: offer.packId);
      purchase = created;
      final url = created.checkoutUrl;
      if (url == null || url.isEmpty) {
        errorMessage = 'Checkout URL missing';
        phase = BuyCreditsPhase.failed;
        notifyListeners();
        return;
      }
      final uri = Uri.parse(url);
      launchedUrls.add(uri);
      final opened = await launchUrl(uri);
      if (!opened) {
        errorMessage = 'Could not open the browser';
        phase = BuyCreditsPhase.failed;
        notifyListeners();
        return;
      }
      phase = BuyCreditsPhase.awaitingBrowser;
      _startPolling();
    } catch (e) {
      errorMessage = e.toString();
      phase = BuyCreditsPhase.failed;
    }
    notifyListeners();
  }

  Future<void> refreshPurchase() async {
    final current = purchase;
    if (current == null) return;
    phase = BuyCreditsPhase.polling;
    notifyListeners();
    try {
      final next = await creditsRepository.getPurchase(current.purchaseId);
      purchase = next;
      if (next.status == CreditPurchaseStatus.paid) {
        _stopPolling();
        phase = BuyCreditsPhase.applied;
        await usageController.load();
      } else if (next.status == CreditPurchaseStatus.expired) {
        _stopPolling();
        phase = BuyCreditsPhase.expired;
      } else {
        phase = BuyCreditsPhase.awaitingBrowser;
      }
    } catch (e) {
      errorMessage = e.toString();
      phase = BuyCreditsPhase.failed;
      _stopPolling();
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    final current = purchase;
    _stopPolling();
    if (current == null || current.status != CreditPurchaseStatus.pending) {
      phase = BuyCreditsPhase.ready;
      purchase = null;
      notifyListeners();
      return;
    }
    try {
      purchase = await creditsRepository.cancelPurchase(current.purchaseId);
    } catch (e) {
      errorMessage = e.toString();
    }
    phase = BuyCreditsPhase.ready;
    notifyListeners();
  }

  void _startPolling() {
    _stopPolling();
    _pollStartedAt = DateTime.now();
    _poll = Timer.periodic(pollInterval, (_) {
      final started = _pollStartedAt;
      if (started != null && DateTime.now().difference(started) > pollCap) {
        _stopPolling();
        return;
      }
      unawaited(refreshPurchase());
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}

final buyCreditsControllerProvider = Provider.autoDispose<BuyCreditsController>(
  (ref) {
    final controller = BuyCreditsController(
      creditsRepository: ref.watch(creditsRepositoryProvider),
      usageController: ref.watch(usageControllerProvider),
      launchUrl: ref.watch(checkoutUrlLauncherProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [
    creditsRepositoryProvider,
    usageControllerProvider,
    checkoutUrlLauncherProvider,
  ],
);
