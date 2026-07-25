import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/media_viewer.dart';

void main() {
  test('containMappedRegion maps normalized box through BoxFit.contain', () {
    final rect = containMappedRegion(
      region: const TagRegion(yMin: 0.25, xMin: 0.25, yMax: 0.75, xMax: 0.75),
      viewport: const Size(200, 100),
      imageSize: const Size(100, 100),
    );
    // Image drawn at 100x100 centered in 200x100 → offset (50, 0).
    expect(rect.left, 75);
    expect(rect.top, 25);
    expect(rect.width, 50);
    expect(rect.height, 50);
  });

  testWidgets('WhoFaceOverlayLayer draws one overlay per who-tag with region',
      (tester) async {
    final who = Tag(
      id: 'tag_who_box',
      itemId: 'item_1',
      dimension: 'who',
      value: 'Sam',
      source: KnowledgeSource.model,
      status: TagStatus.active,
      confidence: 0.9,
      region: const TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.9, xMax: 0.9),
      schemaVersion: 1,
      createdAt: '2026-07-24T00:00:00.000Z',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: WhoFaceOverlayLayer(
              whoOverlays: [who],
              viewport: const Size(200, 200),
              imageSize: const Size(200, 200),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('who-face-overlay-tag_who_box')), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('WhoFaceOverlayLayer draws nothing when overlays list is empty',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 200,
            height: 200,
            child: WhoFaceOverlayLayer(
              whoOverlays: [],
              viewport: Size(200, 200),
              imageSize: Size(200, 200),
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('who-face-overlay-tag_who_box')), findsNothing);
  });
}
