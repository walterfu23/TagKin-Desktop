import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Lists [Correction] overlays from the approved projection (read-only; D12).
///
/// Undo/redo is via the screen LIFO stack (Cmd/Ctrl+Z), not per-row buttons.
class CorrectionsHistoryView extends StatelessWidget {
  const CorrectionsHistoryView({
    super.key,
    required this.corrections,
  });

  final List<Correction> corrections;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('corrections-history'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Corrections',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (corrections.isEmpty)
          const Text(
            'No corrections yet.',
            key: Key('corrections-empty'),
          )
        else
          for (final correction in corrections)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${correction.targetType} · '
                '${_summarize(correction.previousValue)} → '
                '${_summarize(correction.newValue)}',
                key: Key('correction-${correction.id}'),
              ),
            ),
      ],
    );
  }
}

String _summarize(Object? value) {
  if (value == null) return '—';
  if (value is String) return value;
  return value.toString();
}
