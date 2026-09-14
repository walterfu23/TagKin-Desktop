import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/key_period_scrubber.dart';

void main() {
  testWidgets('tapping a key period reports onSelectPeriod', (tester) async {
    const period = KeyPeriodKnowledge(
      id: 'kp2',
      itemId: 'v',
      startMs: 1800,
      endMs: 9000,
      tags: [],
    );
    KeyPeriodKnowledge? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KeyPeriodScrubber(
            keyPeriods: const [period],
            onSelectPeriod: (p) => selected = p,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('key-period-kp2')));
    await tester.pump();
    expect(selected?.id, 'kp2');
    expect(selected?.startMs, 1800);
  });
}
