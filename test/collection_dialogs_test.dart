import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/collection_dialogs.dart';

void main() {
  testWidgets(
      'open collection dialog lists names A–Z case-insensitively',
      (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-collections'),
              onPressed: () async {
                picked = await showOpenCollectionDialog(
                  context,
                  collections: const [
                    (id: 'c_z', name: 'zoo'),
                    (id: 'c_v', name: 'Vacation'),
                    (id: 'c_a', name: 'ada trips'),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-collections')));
    await tester.pumpAndSettle();

    final ada = tester.getTopLeft(
      find.byKey(const Key('collection-open-option-c_a')),
    );
    final vacation = tester.getTopLeft(
      find.byKey(const Key('collection-open-option-c_v')),
    );
    final zoo = tester.getTopLeft(
      find.byKey(const Key('collection-open-option-c_z')),
    );
    expect(ada.dy, lessThan(vacation.dy));
    expect(vacation.dy, lessThan(zoo.dy));

    await tester.tap(find.byKey(const Key('collection-open-option-c_v')));
    await tester.pumpAndSettle();
    expect(picked, 'c_v');
  });
}
