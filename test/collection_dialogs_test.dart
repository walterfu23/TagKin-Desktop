import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/collection_dialogs.dart';
import 'package:tagkin_desktop/persons/collections_controller.dart';

void main() {
  testWidgets('open collection dialog lists names A–Z case-insensitively', (
    tester,
  ) async {
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

  testWidgets('folder claim conflict dialog Move here returns true', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-claim'),
              onPressed: () async {
                result = await showFolderClaimConflictDialog(
                  context,
                  currentCollectionName: 'Trip',
                  conflicts: const [
                    FolderClaimConflict(
                      collectionId: 'c_other',
                      collectionName: 'Vacation',
                      folders: ['/albums/Owned'],
                    ),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-claim')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('collection-folder-claim-dialog')),
      findsOneWidget,
    );
    expect(find.text('Vacation'), findsOneWidget);
    expect(find.text('/albums/Owned'), findsOneWidget);
    expect(find.textContaining('Trip'), findsOneWidget);

    await tester.tap(find.byKey(const Key('collection-folder-claim-move')));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('folder claim conflict dialog Cancel returns false', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const Key('open-claim'),
              onPressed: () async {
                result = await showFolderClaimConflictDialog(
                  context,
                  currentCollectionName: 'Trip',
                  conflicts: const [
                    FolderClaimConflict(
                      collectionId: 'c_other',
                      collectionName: 'Vacation',
                      folders: ['/albums/Owned'],
                    ),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('open-claim')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('collection-folder-claim-cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
