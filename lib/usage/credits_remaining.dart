import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/credits/pack_label.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';

/// Compact Folders-toolbar count from [UsageController.remainingCredits].
///
/// Hidden until a successful `/usage` load so a fetch failure never implies
/// zero. Pass [controller] in widget tests; otherwise watches the provider.
class CreditsRemainingChip extends ConsumerWidget {
  const CreditsRemainingChip({super.key, this.controller});

  final UsageController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UsageController usage =
        controller ?? ref.watch(usageControllerProvider);
    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) {
        final remaining = usage.remainingCredits;
        if (remaining == null) {
          return const SizedBox.shrink(
            key: Key('credits-remaining-chip-hidden'),
          );
        }
        return Tooltip(
          message:
              'Spendable credits, already net of pending analysis holds',
          child: Chip(
            key: const Key('credits-remaining-chip'),
            label: Text('${formatCreditCount(remaining)} credits'),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      },
    );
  }
}

/// Settings > Credits standing count, with a refresh that re-fetches `/usage`.
class CreditsRemainingTile extends ConsumerWidget {
  const CreditsRemainingTile({super.key, this.controller});

  final UsageController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UsageController usage =
        controller ?? ref.watch(usageControllerProvider);
    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) {
        final remaining = usage.remainingCredits;
        final failed = usage.phase == UsagePhase.error;
        final loading = usage.phase == UsagePhase.loading;
        final subtitle = failed
            ? 'Could not load'
            : 'Spendable now, already net of pending analysis holds. '
                'Credits do not expire.';
        return ListTile(
          key: const Key('settings-credits-remaining'),
          title: const Text('Credits remaining'),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading && remaining == null)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Text(
                  remaining == null ? '—' : formatCreditCount(remaining),
                  key: const Key('settings-credits-remaining-value'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              IconButton(
                key: const Key('settings-credits-refresh'),
                tooltip: 'Refresh',
                onPressed: loading ? null : usage.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// “You have N credits.” for Buy / Redeem / Trial. Hidden until loaded.
class CreditsRemainingSentence extends ConsumerWidget {
  const CreditsRemainingSentence({
    super.key,
    required this.textKey,
    this.controller,
  });

  final Key textKey;
  final UsageController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UsageController usage =
        controller ?? ref.watch(usageControllerProvider);
    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) {
        final remaining = usage.remainingCredits;
        if (remaining == null) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'You have ${formatCreditCount(remaining)} credits.',
            key: textKey,
          ),
        );
      },
    );
  }
}
