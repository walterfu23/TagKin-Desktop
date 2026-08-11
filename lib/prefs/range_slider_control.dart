import 'package:flutter/material.dart';

/// Discrete integer slider with a value label that follows the thumb.
class RangeSliderControl extends StatelessWidget {
  const RangeSliderControl({
    super.key,
    this.sliderKey,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.enabled = true,
    this.labelBuilder,
  })  : assert(min <= max),
        assert(step > 0);

  final Key? sliderKey;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;
  final bool enabled;
  final String Function(int value)? labelBuilder;

  static int snap(int value, int min, int max, int step) {
    final clamped = value.clamp(min, max);
    if (step <= 1) return clamped;
    // Round to nearest step multiple so defaults like 500 stay put when
    // min is not step-aligned (e.g. soft max frames: min 1, step 10).
    final snapped = ((clamped / step).round() * step).clamp(min, max);
    return snapped;
  }

  int get _clamped => snap(value, min, max, step);

  int get _divisions {
    final span = max - min;
    if (span <= 0 || step <= 0) return 1;
    return (span / step).round().clamp(1, span);
  }

  double get _fraction =>
      max == min ? 0.0 : (_clamped - min) / (max - min);

  @override
  Widget build(BuildContext context) {
    return _ThumbLabelTrack(
      sliderKey: sliderKey,
      value: _clamped.toDouble(),
      min: min.toDouble(),
      max: max.toDouble(),
      divisions: _divisions,
      fraction: _fraction,
      label: labelBuilder?.call(_clamped) ?? '$_clamped',
      enabled: enabled,
      onChanged: (v) => onChanged(snap(v.round(), min, max, step)),
    );
  }
}

/// Discrete double slider with a value label that follows the thumb.
class DoubleRangeSliderControl extends StatelessWidget {
  const DoubleRangeSliderControl({
    super.key,
    this.sliderKey,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.step,
    this.enabled = true,
    this.labelBuilder,
  })  : assert(min <= max),
        assert(step > 0);

  final Key? sliderKey;
  final double value;
  final double min;
  final double max;
  final double step;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final String Function(double value)? labelBuilder;

  static double snap(double value, double min, double max, double step) {
    final clamped = value.clamp(min, max);
    final snapped = min + (((clamped - min) / step).round() * step);
    return double.parse(snapped.clamp(min, max).toStringAsFixed(4));
  }

  double get _clamped => snap(value, min, max, step);

  int get _divisions {
    final span = max - min;
    if (span <= 0 || step <= 0) return 1;
    return (span / step).round().clamp(1, 10000);
  }

  double get _fraction =>
      max == min ? 0.0 : (_clamped - min) / (max - min);

  @override
  Widget build(BuildContext context) {
    final label = labelBuilder?.call(_clamped) ??
        _clamped
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
    return _ThumbLabelTrack(
      sliderKey: sliderKey,
      value: _clamped,
      min: min,
      max: max,
      divisions: _divisions,
      fraction: _fraction,
      label: label,
      enabled: enabled,
      onChanged: (v) => onChanged(snap(v, min, max, step)),
    );
  }
}

class _ThumbLabelTrack extends StatelessWidget {
  const _ThumbLabelTrack({
    this.sliderKey,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.fraction,
    required this.label,
    required this.onChanged,
    this.enabled = true,
  });

  final Key? sliderKey;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final double fraction;
  final String label;
  final ValueChanged<double> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelWidth = (label.length * 10.0).clamp(24.0, 56.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        const thumbRadius = 12.0;
        const labelHeight = 22.0;
        const sliderHeight = 40.0;
        final trackWidth =
            (constraints.maxWidth - thumbRadius * 2).clamp(0.0, double.infinity);
        final labelLeft = (thumbRadius + trackWidth * fraction - labelWidth / 2)
            .clamp(0.0, constraints.maxWidth - labelWidth);

        return SizedBox(
          height: sliderHeight + labelHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: sliderHeight,
                child: Slider(
                  key: sliderKey,
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: enabled ? onChanged : null,
                ),
              ),
              Positioned(
                left: labelLeft,
                top: sliderHeight,
                width: labelWidth,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: enabled
                        ? null
                        : theme.colorScheme.onSurface.withValues(alpha: 0.38),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
