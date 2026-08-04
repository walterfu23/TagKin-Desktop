import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/collection_dialogs.dart';

void main() {
  testWidgets('delete collection requires typed name', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-delete'),
              onPressed: () async {
                result = await showDeleteCollectionDialog(
                  context,
                  name: 'Vacation',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-delete')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Items and people are unchanged'),
      findsOneWidget,
    );

    final confirm = tester.widget<FilledButton>(
      find.byKey(const Key('collection-delete-confirm')),
    );
    expect(confirm.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('collection-delete-name-field')),
      'Vacation',
    );
    await tester.pump();

    final enabled = tester.widget<FilledButton>(
      find.byKey(const Key('collection-delete-confirm')),
    );
    expect(enabled.onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('collection-delete-confirm')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
