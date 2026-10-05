import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/credits_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/credits/credits_navigation.dart';
import 'package:tagkin_desktop/credits/pack_label.dart';
import 'package:tagkin_desktop/usage/usage_controller.dart';
import 'package:tagkin_desktop/widgets/selectable_scope.dart';

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Local calendar day for an expiry instant, e.g. "Apr 11, 2026".
String formatCreditExpiryDay(DateTime expiresAt) {
  final local = expiresAt.toLocal();
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

class CreditExpiryGroup {
  const CreditExpiryGroup({
    required this.label,
    required this.remainingCredits,
  });

  final String label;
  final int remainingCredits;
}

/// Spendable lots summed by local calendar day, earliest day first.
List<CreditExpiryGroup> groupCreditLotsByLocalDay(List<CreditLot> lots) {
  final sorted = [...lots]..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
  final groups = <CreditExpiryGroup>[];
  for (final lot in sorted) {
    final label = formatCreditExpiryDay(DateTime.parse(lot.expiresAt));
    if (groups.isNotEmpty && groups.last.label == label) {
      final prev = groups.last;
      groups[groups.length - 1] = CreditExpiryGroup(
        label: label,
        remainingCredits: prev.remainingCredits + lot.remainingCredits,
      );
    } else {
      groups.add(
        CreditExpiryGroup(
          label: label,
          remainingCredits: lot.remainingCredits,
        ),
      );
    }
  }
  return groups;
}

/// True when the next pack expires within 48 hours, including one already due.
bool creditExpiryIsSoon(String? nextExpiresAt, {DateTime? now}) {
  if (nextExpiresAt == null || nextExpiresAt.isEmpty) return false;
  final at = DateTime.parse(nextExpiresAt);
  final clock = now ?? DateTime.now();
  return at.difference(clock) <= const Duration(hours: 48);
}

/// Compact Folders-toolbar count from [UsageController.remainingCredits].
///
/// Hidden until a successful `/usage` load so a fetch failure never implies
/// zero. Tap opens remaining credits grouped by expiration date.
/// Pass [controller] in widget tests; otherwise watches the provider.
class CreditsRemainingChip extends ConsumerWidget {
  const CreditsRemainingChip({
    super.key,
    this.controller,
    this.creditsRepository,
  });

  final UsageController? controller;
  final CreditsRepository? creditsRepository;

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
        final soon = creditExpiryIsSoon(usage.summary?.nextExpiresAt);
        final tooltip = soon
            ? 'Some credits expire within 2 days. Tap to see expiration dates.'
            : 'Credits expire. Tap to see expiration dates.';
        return Tooltip(
          message: tooltip,
          child: ActionChip(
            key: const Key('credits-remaining-chip'),
            avatar: Icon(
              Icons.schedule,
              key: soon ? const Key('credits-expire-soon') : null,
              size: 18,
              color: soon ? Colors.amber.shade900 : null,
            ),
            label: Text('${formatCreditCount(remaining)} credits'),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: soon ? Colors.amber.shade100 : null,
            onPressed: () => showCreditLotsDialog(
              context,
              creditsRepository: creditsRepository,
              totalCredits: remaining,
            ),
          ),
        );
      },
    );
  }
}

/// Settings > Credits standing count, with a refresh that re-fetches `/usage`.
/// Tap opens the same expiration breakdown as the Folders chip.
class CreditsRemainingTile extends ConsumerWidget {
  const CreditsRemainingTile({
    super.key,
    this.controller,
    this.creditsRepository,
  });

  final UsageController? controller;
  final CreditsRepository? creditsRepository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UsageController usage =
        controller ?? ref.watch(usageControllerProvider);
    return ListenableBuilder(
      listenable: usage,
      builder: (context, _) {
        final remaining = usage.remainingCredits;
        final days = usage.summary?.creditExpiryDays;
        final failed = usage.phase == UsagePhase.error;
        final loading = usage.phase == UsagePhase.loading;
        final subtitle = failed
            ? 'Could not load'
            : days == null
                ? 'Spendable now, already net of pending analysis holds. '
                    'Credits expire.'
                : 'Spendable now, already net of pending analysis holds. '
                    'Credits expire $days days after you receive them.';
        return ListTile(
          key: const Key('settings-credits-remaining'),
          title: const Text('Credits remaining'),
          subtitle: Text(subtitle),
          onTap: remaining == null
              ? null
              : () => showCreditLotsDialog(
                    context,
                    creditsRepository: creditsRepository,
                    totalCredits: remaining,
                  ),
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
        final days = usage.summary?.creditExpiryDays ?? 7;
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have ${formatCreditCount(remaining)} credits.',
                key: textKey,
              ),
              Text(
                'Credits expire $days days after you receive them.',
                key: const Key('credits-expire-notice'),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> showCreditLotsDialog(
  BuildContext context, {
  required CreditsRepository? creditsRepository,
  required int totalCredits,
}) async {
  if (creditsRepository == null) {
    _snack(context, 'Could not load credit expiration.');
    return;
  }
  CreditLotList loaded;
  try {
    loaded = await creditsRepository.listLots();
  } catch (_) {
    if (context.mounted) {
      _snack(context, 'Could not load credit expiration.');
    }
    return;
  }
  if (!context.mounted) return;
  final groups = groupCreditLotsByLocalDay(loaded.lots);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        key: const Key('credits-lots-dialog'),
        title: const Text('Credits expire'),
        content: SelectableScope(
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatCreditCount(totalCredits)} spendable',
                  key: const Key('credits-lots-total'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Oldest packs are used first. New credits expire '
                  '${loaded.creditExpiryDays} days after you receive them.',
                ),
                const SizedBox(height: 12),
                if (groups.isEmpty)
                  const Text('No credits left to expire.')
                else
                  for (final group in groups)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(child: Text('Expires ${group.label}')),
                          Text(
                            '${formatCreditCount(group.remainingCredits)} credits',
                            key: Key('credits-lots-row-${group.label}'),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('credits-lots-close'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const Key('credits-lots-add-credits'),
            onPressed: () async {
              await Navigator.of(dialogContext).maybePop();
              if (context.mounted) {
                await pushBuyCreditsPage(context);
              }
            },
            child: const Text('Add credits'),
          ),
        ],
      );
    },
  );
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
