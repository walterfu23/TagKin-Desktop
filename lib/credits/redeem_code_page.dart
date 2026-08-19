import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/credits/pack_label.dart';
import 'package:tagkin_desktop/credits/redeem_code_controller.dart';
import 'package:tagkin_desktop/usage/credits_remaining.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

/// Enter a redeem code, preview debt allocation, then confirm.
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

    final previewing = controller.phase == RedeemCodePhase.previewing;
    final redeeming = controller.phase == RedeemCodePhase.redeeming;
    final previewed = controller.phase == RedeemCodePhase.previewed &&
        controller.preview != null;

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
          enabled: !previewing && !redeeming,
          decoration: const InputDecoration(
            labelText: 'Redeem code',
            hintText: 'TK-XXXX-XXXX-XXXX',
          ),
          onChanged: controller.setCode,
          onSubmitted: (_) => controller.previewCode(),
        ),
        if (controller.errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            key: const Key('redeem-code-error'),
            controller.errorMessage!,
          ),
        ],
        if (previewed) ...[
          const SizedBox(height: 16),
          Text(
            key: const Key('redeem-code-disclosure'),
            redeemDebtDisclosure(controller.preview!),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const Key('redeem-code-preview'),
              onPressed: controller.code.trim().isEmpty || previewing || redeeming
                  ? null
                  : controller.previewCode,
              child: const Text('Preview'),
            ),
            FilledButton(
              key: const Key('redeem-code-confirm'),
              onPressed: !previewed || redeeming ? null : controller.confirmRedeem,
              child: const Text('Redeem'),
            ),
          ],
        ),
      ],
    );
  }
}
