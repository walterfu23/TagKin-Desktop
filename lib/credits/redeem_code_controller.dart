import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/credits_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show creditsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

enum RedeemCodePhase {
  idle,
  previewing,
  previewed,
  redeeming,
  applied,
  failed,
}

class RedeemCodeController extends ChangeNotifier {
  RedeemCodeController({
    required this.creditsRepository,
    required this.usageController,
  });

  final CreditsRepository creditsRepository;
  final UsageController usageController;

  RedeemCodePhase phase = RedeemCodePhase.idle;
  String code = '';
  RedeemPreview? preview;
  RedeemResult? result;
  String? errorMessage;

  void setCode(String value) {
    code = value;
    if (phase == RedeemCodePhase.previewed || phase == RedeemCodePhase.failed) {
      preview = null;
      phase = RedeemCodePhase.idle;
      errorMessage = null;
    }
    notifyListeners();
  }

  Future<void> previewCode() async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    phase = RedeemCodePhase.previewing;
    errorMessage = null;
    preview = null;
    notifyListeners();
    try {
      preview = await creditsRepository.previewRedeem(trimmed);
      phase = RedeemCodePhase.previewed;
    } catch (e) {
      errorMessage = _messageFor(e);
      phase = RedeemCodePhase.failed;
    }
    notifyListeners();
  }

  Future<void> confirmRedeem() async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || preview == null) return;
    phase = RedeemCodePhase.redeeming;
    errorMessage = null;
    notifyListeners();
    try {
      result = await creditsRepository.redeem(trimmed);
      phase = RedeemCodePhase.applied;
      await usageController.load();
    } catch (e) {
      errorMessage = _messageFor(e);
      phase = RedeemCodePhase.failed;
    }
    notifyListeners();
  }

  static String _messageFor(Object e) {
    if (e is ApiException) {
      switch (e.code) {
        case 'redeemCodeInvalid':
          return 'That code is not valid.';
        case 'redeemCodeExpired':
          return 'That code has expired.';
        case 'redeemCodeAlreadyUsed':
          return 'That code has already been used.';
        case 'redeemRateLimited':
          return 'Too many attempts. Try again later.';
        default:
          return e.message;
      }
    }
    return e.toString();
  }
}

final redeemCodeControllerProvider = Provider.autoDispose<RedeemCodeController>(
  (ref) {
    final controller = RedeemCodeController(
      creditsRepository: ref.watch(creditsRepositoryProvider),
      usageController: ref.watch(usageControllerProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [
    creditsRepositoryProvider,
    usageControllerProvider,
  ],
);
