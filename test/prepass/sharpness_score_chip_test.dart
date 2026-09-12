import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/sharpness_score_chip.dart';

import '../fake_items_repository.dart';

void main() {
  testWidgets('photo shows rounded stored score', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SharpnessScoreChip(
          item: fixtureItem(id: 'p', sharpness: 8583.4),
        ),
      ),
    );
    expect(find.text('8583'), findsOneWidget);
  });

  testWidgets('null stored score shows an em dash', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SharpnessScoreChip(item: fixtureItem(id: 'p')),
      ),
    );
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('video is empty', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SharpnessScoreChip(
          item: fixtureItem(id: 'v', type: ItemType.video, sharpness: 10),
        ),
      ),
    );
    expect(find.text('10'), findsNothing);
    expect(find.text('—'), findsNothing);
  });
}
