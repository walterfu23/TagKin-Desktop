import 'package:flutter/material.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Display mapping for [LinkState] (D9). Labels use canonical terms (R2).
class LinkStateView {
  const LinkStateView({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  static LinkStateView of(LinkState state) {
    switch (state) {
      case LinkState.suggested:
        return const LinkStateView(
          label: 'suggested',
          icon: Icons.help_outline,
          color: Color(0xFFD97706),
        );
      case LinkState.confirmed:
        return const LinkStateView(
          label: 'confirmed',
          icon: Icons.check_circle_outline,
          color: Color(0xFF059669),
        );
    }
  }
}

/// Compact badge showing a person's or appearance's [LinkState].
class LinkStateBadge extends StatelessWidget {
  const LinkStateBadge({super.key, required this.linkState});

  final LinkState linkState;

  @override
  Widget build(BuildContext context) {
    final view = LinkStateView.of(linkState);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(view.icon, size: 16, color: view.color),
        const SizedBox(width: 4),
        Text(
          view.label,
          key: Key('link-state-${linkState.wire}'),
          style: TextStyle(color: view.color, fontSize: 13),
        ),
      ],
    );
  }
}
