import 'package:flutter/material.dart';
import 'package:tagkin_desktop/usage/usage_gate.dart';

/// Warn / blocked banner driven by [UsageGate]. Hidden when neither applies.
class UsageBanner extends StatelessWidget {
  const UsageBanner({super.key, required this.gate});

  final UsageGate gate;

  @override
  Widget build(BuildContext context) {
    if (!gate.blocked && !gate.warn) {
      return const SizedBox.shrink(key: Key('usage-banner-hidden'));
    }

    if (gate.blocked) {
      final reason = gate.reasonText;
      final message = reason == null || reason.isEmpty
          ? 'Ingest paused.'
          : 'Ingest paused: $reason';
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
                  key: const Key('usage-banner-blocked'),
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
                '80% of budget used',
                key: const Key('usage-banner-warn'),
                style: TextStyle(color: Colors.amber.shade900),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
