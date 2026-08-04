import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/prefs/range_slider_control.dart';

void main() {
  test('RangeSliderControl.snap rounds to step multiples', () {
    expect(RangeSliderControl.snap(500, 10, 2000, 10), 500);
    expect(RangeSliderControl.snap(1, 10, 2000, 10), 10);
    expect(RangeSliderControl.snap(505, 10, 2000, 10), 510);
    expect(RangeSliderControl.snap(4, 0, 64, 1), 4);
    expect(RangeSliderControl.snap(150, 100, 60000, 100), 200);
  });

  test('DoubleRangeSliderControl.snap stays on step grid', () {
    expect(
      DoubleRangeSliderControl.snap(0.3, 0.05, 0.9, 0.05),
      closeTo(0.3, 1e-9),
    );
    expect(
      DoubleRangeSliderControl.snap(0.22, 0.05, 0.95, 0.05),
      closeTo(0.2, 1e-9),
    );
  });

  testWidgets('RangeSliderControl shows thumb label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RangeSliderControl(
            sliderKey: const Key('test-slider'),
            value: 12,
            min: 1,
            max: 30,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('test-slider')), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });
}
