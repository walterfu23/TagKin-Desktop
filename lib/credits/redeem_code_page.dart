import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/credits/pack_label.dart';
import 'package:tagkin_desktop/credits/redeem_code_controller.dart';
import 'package:tagkin_desktop/usage/credits_remaining.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Enter a redeem code. Redeem validates it, then a dialog confirms the
/// server debt split before the code is consumed.
class RedeemCodePage extends ConsumerStatefulWidget {
  const RedeemCodePage({super.key});

  @override
  ConsumerState<RedeemCodePage> createState() => _RedeemCodePageState();
}

class _RedeemCodePageState extends ConsumerState<RedeemCodePage> {
  late final TextEditingController _codeController;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(usageControllerProvider).ensureLoaded();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(redeemCodeControllerProvider);
    return SelectableScope(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          return Scaffold(
            appBar: AppBar(title: const Text('Redeem code')),
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: _body(controller),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _body(RedeemCodeController controller) {
    if (controller.phase == RedeemCodePhase.applied) {
      return Column(
        key: const Key('redeem-code-applied'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Credits applied. Remaining: '
            '${formatCreditCount(controller.result?.remainingCredits ?? 0)}.',
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('redeem-code-done'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      );
    }

    final busy = controller.phase == RedeemCodePhase.previewing ||
        controller.phase == RedeemCodePhase.redeeming;
    final canRedeem = controller.code.trim().isNotEmpty && !busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CreditsRemainingSentence(
          textKey: Key('redeem-code-remaining'),
        ),
        const Text(
          'Enter a redeem code. Credits do not expire.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('redeem-code-input'),
          controller: _codeController,
          autofocus: true,
          enabled: !busy,
          decoration: const InputDecoration(
            labelText: 'Redeem code',
            hintText: 'TK-XXXX-XXXX-XXXX',
          ),
          onChanged: controller.setCode,
          onSubmitted: (_) {
            if (canRedeem) _startRedeem(controller);
          },
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            key: const Key('redeem-code-error'),
            controller.errorMessage!,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('redeem-code-redeem'),
          onPressed: canRedeem ? () => _startRedeem(controller) : null,
          child: const Text('Redeem'),
        ),
      ],
    );
  }

  Future<void> _startRedeem(RedeemCodeController controller) async {
    await controller.previewCode();
    if (!mounted) return;
    final preview = controller.preview;
    if (controller.phase != RedeemCodePhase.previewed || preview == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => SelectableScope(
        child: AlertDialog(
          title: const Text('Redeem this code?'),
          content: Text(
            key: const Key('redeem-code-disclosure'),
            redeemDebtDisclosure(preview),
          ),
          actions: [
            TextButton(
              key: const Key('redeem-code-cancel'),
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const Key('redeem-code-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Redeem'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    await controller.confirmRedeem();
    if (!mounted || controller.phase != RedeemCodePhase.applied) return;
    Navigator.of(context).popUntil((route) {
      final name = route.settings.name;
      return name != 'redeem-code' && name != 'buy-credits';
    });
  }
}
