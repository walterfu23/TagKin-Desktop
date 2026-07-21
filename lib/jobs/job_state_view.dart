import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Whether [state] is a terminal job lifecycle value (polling should stop).
bool isTerminalJobState(JobState state) {
  switch (state) {
    case JobState.completed:
    case JobState.failed:
    case JobState.cancelled:
      return true;
    case JobState.queued:
    case JobState.awaitingModelAccess:
    case JobState.reserved:
    case JobState.processing:
    case JobState.pausedForBudget:
      return false;
  }
}

/// Display mapping for [JobState] (D7). Labels use canonical terms (R2).
class JobStateView {
  const JobStateView({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  static JobStateView of(JobState state) {
    switch (state) {
      case JobState.queued:
        return const JobStateView(
          label: 'queued',
          icon: Icons.schedule,
          color: Color(0xFF6B7280),
        );
      case JobState.awaitingModelAccess:
        return const JobStateView(
          label: 'awaiting model access',
          icon: Icons.cloud_outlined,
          color: Color(0xFF2563EB),
        );
      case JobState.reserved:
        return const JobStateView(
          label: 'reserved',
          icon: Icons.lock_outline,
          color: Color(0xFF7C3AED),
        );
      case JobState.processing:
        return const JobStateView(
          label: 'processing',
          icon: Icons.autorenew,
          color: Color(0xFFD97706),
        );
      case JobState.pausedForBudget:
        return const JobStateView(
          label: 'paused for budget',
          icon: Icons.pause_circle_outline,
          color: Color(0xFFDC2626),
        );
      case JobState.completed:
        return const JobStateView(
          label: 'completed',
          icon: Icons.check_circle_outline,
          color: Color(0xFF059669),
        );
      case JobState.failed:
        return const JobStateView(
          label: 'failed',
          icon: Icons.error_outline,
          color: Color(0xFFDC2626),
        );
      case JobState.cancelled:
        return const JobStateView(
          label: 'cancelled',
          icon: Icons.cancel_outlined,
          color: Color(0xFF6B7280),
        );
    }
  }
}

/// Compact badge showing a [Job]'s [JobState].
class JobStateBadge extends StatelessWidget {
  const JobStateBadge({super.key, required this.state});

  final JobState state;

  @override
  Widget build(BuildContext context) {
    final view = JobStateView.of(state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(view.icon, size: 16, color: view.color),
        const SizedBox(width: 4),
        Text(
          view.label,
          key: Key('job-state-${state.wire}'),
          style: TextStyle(color: view.color, fontSize: 13),
        ),
      ],
    );
  }
}
