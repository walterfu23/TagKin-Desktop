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
  });

  final UsageGate gate;
  final String? analyzeRejectCode;
  final String? analyzeRejectMessage;

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
      );
    }

    if (insufficient) {
      return _blocked(
        context,
        'Not enough credits for this analysis',
        const Key('usage-banner-insufficient-credits'),
      );
    }

    if (lowCredits) {
      return _warn(
        context,
        'Only ${gate.remainingCredits} credits remaining',
        const Key('usage-banner-low-credits'),
      );
    }

    if (gate.blocked) {
      final reason = gate.reasonText;
      final message = reason == null || reason.isEmpty
          ? 'Ingest paused.'
          : 'Ingest paused: $reason';
      return _blocked(context, message, const Key('usage-banner-blocked'));
    }

    if (gate.warn || gate.notice == UsageNotice.budgetWarn) {
      return _warn(
        context,
        '80% of budget used',
        const Key('usage-banner-warn'),
      );
    }

    return const SizedBox.shrink(key: Key('usage-banner-hidden'));
  }

  Widget _blocked(BuildContext context, String message, Key textKey) {
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
          ],
        ),
      ),
    );
  }

  Widget _warn(BuildContext context, String message, Key textKey) {
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
          ],
        ),
      ),
    );
  }
}
