import 'dart:async';

import 'package:flutter/material.dart';

/// Cliptorium-style two-tap confirm: idle icon → red "Sure?" → [onConfirm].
class SureActionButton extends StatefulWidget {
  const SureActionButton({
    super.key,
    required this.idleKey,
    required this.confirmKey,
    required this.tooltip,
    required this.confirmSemanticsLabel,
    required this.icon,
    required this.onConfirm,
    this.enabled = true,
    this.iconSize,
    this.visualDensity,
    this.padding,
    this.constraints,
  });

  final Key idleKey;
  final Key confirmKey;
  final String tooltip;
  final String confirmSemanticsLabel;
  final Widget icon;
  final VoidCallback onConfirm;
  final bool enabled;
  final double? iconSize;
  final VisualDensity? visualDensity;
  final EdgeInsetsGeometry? padding;
  final BoxConstraints? constraints;

  @override
  State<SureActionButton> createState() => _SureActionButtonState();
}

class _SureActionButtonState extends State<SureActionButton> {
  static const _confirmTimeout = Duration(seconds: 3);

  bool _armed = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(SureActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _armed) {
      _timer?.cancel();
      _armed = false;
    }
  }

  void _onPressed() {
    if (!widget.enabled) return;
    if (!_armed) {
      setState(() => _armed = true);
      _timer?.cancel();
      _timer = Timer(_confirmTimeout, () {
        if (mounted) setState(() => _armed = false);
      });
      return;
    }
    _timer?.cancel();
    setState(() => _armed = false);
    widget.onConfirm();
  }

  @override
  Widget build(BuildContext context) {
    if (_armed) {
      final radius = BorderRadius.circular(6);
      return Semantics(
        label: widget.confirmSemanticsLabel,
        button: true,
        child: Material(
          key: widget.confirmKey,
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: _onPressed,
            borderRadius: radius,
            child: SizedBox(
              width: 52,
              height: 40,
              child: Center(
                child: Text(
                  'Sure?',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return IconButton(
      key: widget.idleKey,
      tooltip: widget.tooltip,
      icon: widget.icon,
      iconSize: widget.iconSize,
      visualDensity: widget.visualDensity,
      padding: widget.padding,
      constraints: widget.constraints,
      onPressed: widget.enabled ? _onPressed : null,
    );
  }
}
