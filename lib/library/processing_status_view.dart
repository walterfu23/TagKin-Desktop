import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Display mapping for [ProcessingStatus] (D2). Labels use canonical terms (R2).
class ProcessingStatusView {
  const ProcessingStatusView({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Maps every [ProcessingStatus] wire value to a stable UI presentation.
  static ProcessingStatusView of(ProcessingStatus status) {
    switch (status) {
      case ProcessingStatus.pending:
        return const ProcessingStatusView(
          label: 'pending',
          icon: Icons.schedule,
          color: Color(0xFF6B7280),
        );
      case ProcessingStatus.awaitingModelAccess:
        return const ProcessingStatusView(
          label: 'awaiting model access',
          icon: Icons.cloud_upload_outlined,
          color: Color(0xFF2563EB),
        );
      case ProcessingStatus.processing:
        return const ProcessingStatusView(
          label: 'processing',
          icon: Icons.autorenew,
          color: Color(0xFFD97706),
        );
      case ProcessingStatus.tagged:
        return const ProcessingStatusView(
          label: 'tagged',
          icon: Icons.check_circle_outline,
          color: Color(0xFF059669),
        );
      case ProcessingStatus.failed:
        return const ProcessingStatusView(
          label: 'failed',
          icon: Icons.error_outline,
          color: Color(0xFFDC2626),
        );
      case ProcessingStatus.cancelled:
        return const ProcessingStatusView(
          label: 'cancelled',
          icon: Icons.cancel_outlined,
          color: Color(0xFF6B7280),
        );
      case ProcessingStatus.refused:
        return const ProcessingStatusView(
          label: 'refused',
          icon: Icons.block,
          color: Color(0xFFB45309),
        );
    }
  }
}

/// Compact badge showing [item]'s [ProcessingStatus].
class ProcessingStatusBadge extends StatelessWidget {
  const ProcessingStatusBadge({
    super.key,
    required this.status,
    this.processingError,
    this.refusalMessage,
  });

  final ProcessingStatus status;
  final String? processingError;

  /// Hover text for a model-host refusal. Shown for [ProcessingStatus.refused]
  /// and for a tagged video segment that was refused.
  final String? refusalMessage;

  @override
  Widget build(BuildContext context) {
    final view = ProcessingStatusView.of(status);
    final badge = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(view.icon, size: 16, color: view.color),
        const SizedBox(width: 4),
        Text(
          view.label,
          key: Key('processing-status-${status.wire}'),
          style: TextStyle(color: view.color, fontSize: 13),
        ),
      ],
    );
    final err = processingError?.trim();
    final refusal = refusalMessage?.trim();
    final tip = status == ProcessingStatus.refused
        ? (refusal != null && refusal.isNotEmpty ? 'Refused: $refusal' : null)
        : status == ProcessingStatus.failed && err != null && err.isNotEmpty
            ? err
            : refusal != null && refusal.isNotEmpty
                ? 'Refused: $refusal'
                : null;
    if (tip != null) {
      return Tooltip(
        key: const Key('processing-status-error-tooltip'),
        message: tip,
        waitDuration: Duration.zero,
        child: badge,
      );
    }
    return badge;
  }
}

/// A refused video segment shows Refused on its own row while the item stays tagged.
ProcessingStatus foldersRowStatus(
  ProcessingStatus itemStatus,
  RefusalReason? periodReason,
) {
  if (periodReason != null) return ProcessingStatus.refused;
  return itemStatus;
}

String refusalReasonSentence(RefusalReason reason) {
  switch (reason) {
    case RefusalReason.prohibited:
      return 'The model host refused this as prohibited content.';
    case RefusalReason.blocked:
      return 'The model host blocked this.';
  }
}
