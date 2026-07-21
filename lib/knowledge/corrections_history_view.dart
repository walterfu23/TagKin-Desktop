import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Lists [Correction] overlays from the approved projection with Undo (D10).
class CorrectionsHistoryView extends StatelessWidget {
  const CorrectionsHistoryView({
    super.key,
    required this.corrections,
    this.onUndo,
    this.enabled = true,
  });

  final List<Correction> corrections;
  final void Function(String correctionId)? onUndo;
  final bool enabled;

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
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${correction.targetType} · '
                      '${_summarize(correction.previousValue)} → '
                      '${_summarize(correction.newValue)}',
                      key: Key('correction-${correction.id}'),
                    ),
                  ),
                  if (onUndo != null)
                    TextButton(
                      key: Key('correction-undo-${correction.id}'),
                      onPressed:
                          enabled ? () => onUndo!(correction.id) : null,
                      child: const Text('Undo'),
                    ),
                ],
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
