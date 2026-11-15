import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/review/face_name_conflict_dialog.dart';

import 'fake_items_repository.dart';

void main() {
  group('ConflictFace.label', () {
    test('numbered and named', () {
      const face = ConflictFace(
        itemId: 'i',
        tagId: 't',
        name: 'Maya',
        number: 1,
      );
      expect(face.label, '1 Maya');
    });

    test('empty or blank name reads Unassigned', () {
      expect(
        const ConflictFace(itemId: 'i', tagId: 't', name: null).label,
        'Unassigned',
      );
      expect(
        const ConflictFace(
          itemId: 'i',
          tagId: 't',
          name: '  ',
          number: 2,
        ).label,
        '2 Unassigned',
      );
    });

    test('unnumbered surfaces show the name alone', () {
      expect(
        const ConflictFace(itemId: 'i', tagId: 't', name: 'Sam').label,
        'Sam',
      );
    });
  });

  group('showFaceNameConflictDialog', () {
    Future<bool?> open(WidgetTester tester, Future<void> Function() act) async {
      final item = fixtureItem(id: 'item_1');
      bool? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            itemsRepositoryProvider.overrideWithValue(
              FakeItemsRepository(items: [item]),
            ),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('open'),
                  onPressed: () async {
                    result = await showFaceNameConflictDialog(
                      context,
                      personName: 'Maya',
                      target: const ConflictFace(
                        itemId: 'item_1',
                        tagId: 'tag_t',
                        name: '',
                        number: 2,
                      ),
                      holder: const ConflictFace(
                        itemId: 'item_1',
                        tagId: 'tag_h',
                        name: 'Maya',
                        number: 1,
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('face-name-conflict-dialog')),
        findsOneWidget,
      );
      expect(find.text('Maya is already on another face'), findsOneWidget);
      expect(find.text('2 Unassigned'), findsOneWidget);
      expect(find.text('1 Maya'), findsOneWidget);
      await act();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('face-name-conflict-dialog')), findsNothing);
      return result;
    }

    testWidgets('choosing the face being named returns true', (tester) async {
      final result = await open(
        tester,
        () =>
            tester.tap(find.byKey(const Key('face-name-conflict-pick-tag_t'))),
      );
      expect(result, isTrue);
    });

    testWidgets('choosing the current holder returns false', (tester) async {
      final result = await open(
        tester,
        () =>
            tester.tap(find.byKey(const Key('face-name-conflict-pick-tag_h'))),
      );
      expect(result, isFalse);
    });

    testWidgets('Cancel returns false', (tester) async {
      final result = await open(
        tester,
        () => tester.tap(find.byKey(const Key('face-name-conflict-cancel'))),
      );
      expect(result, isFalse);
    });

    testWidgets('dismissing the barrier returns false', (tester) async {
      final result = await open(tester, () => tester.tapAt(const Offset(2, 2)));
      expect(result, isFalse);
    });

    testWidgets('dialog text is selectable', (tester) async {
      await open(tester, () async {
        expect(
          find.descendant(
            of: find.byKey(const Key('face-name-conflict-dialog')),
            matching: find.byType(SelectionArea),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('face-name-conflict-cancel')));
      });
    });
  });
}
