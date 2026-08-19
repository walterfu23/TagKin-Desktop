import 'package:flutter/material.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';

/// Warn / blocked banner driven by [UsageGate] plus an optional analyze 409.
/// Hidden when neither a meter warning nor a reject applies.
class UsageBanner extends StatelessWidget {
  const UsageBanner({
    super.key,
    required this.gate,
    this.analyzeRejectCode,
    this.analyzeRejectMessage,
    this.onBuyCredits,
  });

  final UsageGate gate;
  final String? analyzeRejectCode;
  final String? analyzeRejectMessage;
  final VoidCallback? onBuyCredits;

  @override
  Widget build(BuildContext context) {
    final reject = analyzeRejectCode;
    final pausedByOperator = gate.notice == UsageNotice.budgetBlocked ||
        reject == 'paidPaused';
    final outOfCredits = gate.notice == UsageNotice.outOfCredits ||
        reject == 'outOfCredits';
    final insufficient = reject == 'insufficientCredits';
    final lowCredits = gate.notice == UsageNotice.lowCredits;

    if (pausedByOperator) {
      final reason = analyzeRejectMessage ?? gate.reasonText;
      final message = reason == null || reason.isEmpty
          ? 'Ingest paused.'
          : 'Ingest paused: $reason';
      return _blocked(context, message, const Key('usage-banner-blocked'));
    }

    if (outOfCredits) {
      return _blocked(
        context,
        'Out of credits',
        const Key('usage-banner-out-of-credits'),
        action: onBuyCredits,
      );
    }

    if (insufficient) {
      return _blocked(
        context,
        'Not enough credits for this analysis',
        const Key('usage-banner-insufficient-credits'),
        action: onBuyCredits,
      );
    }

    if (lowCredits) {
      return _warn(
        context,
        'Only ${gate.remainingCredits} credits remaining',
        const Key('usage-banner-low-credits'),
        action: onBuyCredits,
      );
    }

    if (gate.blocked) {
      final reason = gate.reasonText;
      final message = reason == null || reason.isEmpty
          ? 'Ingest paused.'
          : 'Ingest paused: $reason';
      return _blocked(context, message, const Key('usage-banner-blocked'));
    }

    return const SizedBox.shrink(key: Key('usage-banner-hidden'));
  }

  Widget _blocked(
    BuildContext context,
    String message,
    Key textKey, {
    VoidCallback? action,
  }) {
    return Material(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.block,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                key: textKey,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            if (action != null)
              TextButton(
                key: const Key('usage-banner-buy-credits'),
                onPressed: action,
                child: const Text('Buy credits'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _warn(
    BuildContext context,
    String message,
    Key textKey, {
    VoidCallback? action,
  }) {
    return Material(
      color: Colors.amber.shade100,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.amber.shade900),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                key: textKey,
                style: TextStyle(color: Colors.amber.shade900),
              ),
            ),
            if (action != null)
              TextButton(
                key: const Key('usage-banner-buy-credits'),
                onPressed: action,
                child: const Text('Buy credits'),
              ),
          ],
        ),
      ),
    );
  }
}
