import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/app_shell.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_picker_dialog.dart';
import 'package:tagkin_desktop/persons/who_face_crop_thumb.dart';

import 'fake_persons_repository.dart';

Person _p(String id, String name) =>
    Person(id: id, name: name, createdAt: '2026-09-08T00:00:00.000Z');

class _PickerResult {
  ({String? personId, String? name, bool createNew})? value;
}

Future<_PickerResult> _openPicker(
  WidgetTester tester, {
  required List<Person> persons,
  Set<String> disabledPersonIds = const {},
  List<String> inFolderPersonIds = const [],
  List<String> recentPersonIds = const [],
}) async {
  final result = _PickerResult();
  final fake = FakePersonsRepository(
    persons: [
      for (final p in persons)
        fixturePersonDetail(id: p.id, name: p.name, appearances: const []),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [personsRepositoryProvider.overrideWithValue(fake)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            key: const Key('open-picker'),
            onPressed: () async {
              result.value = await showPersonPickerDialog(
                context,
                persons: persons,
                disabledPersonIds: disabledPersonIds,
                inFolderPersonIds: inFolderPersonIds,
                recentPersonIds: recentPersonIds,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-picker')));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  setUp(PersonAppearanceMemo.instance.clear);
  tearDown(PersonAppearanceMemo.instance.clear);

  testWidgets('search narrows the list', (tester) async {
    await _openPicker(
      tester,
      persons: [_p('sam', 'Sam'), _p('lisa', 'Lisa'), _p('ada', 'Ada')],
    );
    expect(find.byKey(const Key('person-picker-option-sam')), findsOneWidget);
    expect(find.byKey(const Key('person-picker-option-lisa')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('person-picker-search')), 'sa');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('person-picker-option-sam')), findsOneWidget);
    expect(find.byKey(const Key('person-picker-option-lisa')), findsOneWidget);
    expect(find.byKey(const Key('person-picker-option-ada')), findsNothing);
    expect(find.byKey(const Key('person-picker-create')), findsOneWidget);
  });

  testWidgets('selecting an existing person returns id and never a name', (
    tester,
  ) async {
    final result = await _openPicker(
      tester,
      persons: [_p('person_1', 'Person1')],
    );
    await tester.tap(find.byKey(const Key('person-picker-option-person_1')));
    await tester.pumpAndSettle();
    expect(result.value?.personId, 'person_1');
    expect(result.value?.name, isNull);
  });

  testWidgets('New person is offered before anything is typed', (tester) async {
    final result = await _openPicker(
      tester,
      persons: [_p('sam', 'Sam'), _p('lisa', 'Lisa')],
    );
    expect(find.byKey(const Key('person-picker-create')), findsOneWidget);
    expect(find.text('New person'), findsOneWidget);

    await tester.tap(find.byKey(const Key('person-picker-create')));
    await tester.pumpAndSettle();

    expect(result.value?.createNew, isTrue);
    expect(result.value?.personId, isNull);
    expect(result.value?.name, isNull);
  });

  testWidgets('exact name match keeps New person but not Create', (
    tester,
  ) async {
    await _openPicker(tester, persons: [_p('sam', 'Sam')]);
    await tester.enterText(find.byKey(const Key('person-picker-search')), 'sam');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-picker-create')), findsOneWidget);
    expect(find.text('New person'), findsOneWidget);
    expect(find.textContaining('Create new person'), findsNothing);
    expect(find.byKey(const Key('person-picker-option-sam')), findsOneWidget);
  });

  testWidgets('create row mints a new name when it does not collide', (
    tester,
  ) async {
    final result = await _openPicker(tester, persons: [_p('sam', 'Sam')]);
    await tester.enterText(
      find.byKey(const Key('person-picker-search')),
      'Riley',
    );
    await tester.pumpAndSettle();
    expect(find.text('Create new person "Riley"'), findsOneWidget);
    await tester.tap(find.byKey(const Key('person-picker-create')));
    await tester.pumpAndSettle();
    expect(result.value?.personId, isNull);
    expect(result.value?.name, 'Riley');
    expect(result.value?.createNew, isFalse);
  });

  testWidgets('disabled same-photo rows are not committable', (tester) async {
    final result = await _openPicker(
      tester,
      persons: [_p('sam', 'Sam'), _p('ada', 'Ada')],
      disabledPersonIds: {'sam'},
    );
    final tile = tester.widget<ListTile>(
      find.byKey(const Key('person-picker-option-sam')),
    );
    expect(tile.enabled, isFalse);
    expect(find.text('already on this photo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('person-picker-option-sam')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('person-picker-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('person-picker-cancel')));
    await tester.pumpAndSettle();
    expect(result.value, isNull);
  });

  testWidgets('large roster virtualizes rows under the result cap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _openPicker(
      tester,
      persons: [
        for (var i = 0; i < 200; i++)
          _p('p$i', 'Person ${i.toString().padLeft(3, '0')}'),
      ],
    );
    final list = tester.widget<ListView>(
      find.byKey(const Key('person-picker-list')),
    );
    expect(
      list.semanticChildCount,
      103,
      reason:
          'New person + header + 100 people + truncated footer, even if '
          'off-screen',
    );
    expect(
      tester.widgetList(find.byType(ListTile)).length,
      lessThan(40),
      reason: 'ListView.builder should only mount a screenful of rows',
    );
  });
}
