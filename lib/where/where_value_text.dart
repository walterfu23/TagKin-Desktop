import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/where/where_label_resolver.dart';
import 'package:tagkin_desktop/where/where_place_label.dart';

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

/// Resolves where-tag values, drops redundant labels, shows CSV.
class WhereValuesText extends ConsumerStatefulWidget {
  const WhereValuesText({
    super.key,
    required this.values,
    this.style,
  });

  final List<String> values;
  final TextStyle? style;

  @override
  ConsumerState<WhereValuesText> createState() => _WhereValuesTextState();
}

class _WhereValuesTextState extends ConsumerState<WhereValuesText> {
  List<String>? _labels;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant WhereValuesText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.values, widget.values)) {
      _labels = null;
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final raw = List<String>.from(widget.values);
    final resolved = collapseWhereDisplays(
      await ref.read(whereLabelResolverProvider).resolveAllDisplays(raw),
    );
    if (!mounted || !listEquals(widget.values, raw)) return;
    setState(() => _labels = [for (final e in resolved) e.label]);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _labels ?? widget.values;
    if (shown.isEmpty) return Text('—', style: widget.style);
    return Text(
      shown.join(', '),
      style: widget.style,
    );
  }
}
