import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';

/// Shows a where-tag value as city/state (GPS) or the raw label otherwise.
class WhereValueText extends ConsumerStatefulWidget {
  const WhereValueText({
    super.key,
    required this.value,
    this.style,
  });

  final String value;
  final TextStyle? style;

  @override
  ConsumerState<WhereValueText> createState() => _WhereValueTextState();
}

class _WhereValueTextState extends ConsumerState<WhereValueText> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant WhereValueText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _label = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final raw = widget.value;
    final resolved =
        await ref.read(whereLabelResolverProvider).resolve(raw);
    if (!mounted || widget.value != raw) return;
    setState(() => _label = resolved);
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label ?? widget.value,
      style: widget.style,
    );
  }
}
