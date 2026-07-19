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
    }
  }
}

/// Compact badge showing [item]'s [ProcessingStatus].
class ProcessingStatusBadge extends StatelessWidget {
  const ProcessingStatusBadge({super.key, required this.status});

  final ProcessingStatus status;

  @override
  Widget build(BuildContext context) {
    final view = ProcessingStatusView.of(status);
    return Row(
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
  }
}
