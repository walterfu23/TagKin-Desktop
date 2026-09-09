import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_messages.dart';
import 'package:tagkin_desktop/api/credits_repository.dart';
import 'package:tagkin_desktop/app_shell.dart'
    show checkoutUrlLauncherProvider, creditsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/checkout_launcher.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

/// Card-setup Trial pack: load eligibility, open Checkout, then claim.
class TrialCardController extends ChangeNotifier {
  TrialCardController({
    required this.creditsRepository,
    required this.usageController,
    required this.launchUrl,
  });

  final CreditsRepository creditsRepository;
  final UsageController usageController;
  final CheckoutUrlLauncher launchUrl;

  TrialSummary? summary;
  String? errorMessage;
  String? verificationId;
  bool busy = false;
  bool granted = false;

  Future<void> load() async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      summary = await creditsRepository.getTrial();
    } catch (e) {
      errorMessage = apiUserMessage(e);
    }
    busy = false;
    notifyListeners();
  }

  Future<void> start() async {
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final created = await creditsRepository.startTrialVerification();
      verificationId = created.verificationId;
      final opened = await launchUrl(Uri.parse(created.cardSetupUrl));
      if (!opened) {
        errorMessage = 'Could not open the browser';
      }
    } catch (e) {
      errorMessage = apiUserMessage(e);
    }
    busy = false;
    notifyListeners();
  }

  Future<void> claim() async {
    final id = verificationId;
    if (id == null) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await creditsRepository.claimTrialVerification(id);
      granted = result.status == TrialStatus.granted.wire;
      await usageController.load();
    } catch (e) {
      errorMessage = apiUserMessage(e);
    }
    busy = false;
    notifyListeners();
  }
}

final trialCardControllerProvider = Provider.autoDispose<TrialCardController>(
  (ref) {
    final controller = TrialCardController(
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
