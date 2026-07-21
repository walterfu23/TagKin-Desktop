import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';

import 'fake_persons_repository.dart';

void main() {
  group('PersonDetailController', () {
    test('load populates detail; confirm moves suggested → confirmed',
        () async {
      final repo = FakePersonsRepository(
        persons: [
          fixturePersonDetail(
            id: 'person_1',
            name: 'Sam',
            linkState: LinkState.suggested,
          ),
        ],
      );
      final controller = PersonDetailController(
        personId: 'person_1',
        personsRepository: repo,
      );

      await controller.load();
      expect(controller.phase, PersonDetailPhase.ready);
      expect(controller.detail!.linkState, LinkState.suggested);
      expect(controller.canConfirm, isTrue);

      await controller.confirm();
      expect(controller.detail!.linkState, LinkState.confirmed);
      expect(controller.detail!.appearances.single.linkState,
          LinkState.confirmed);
      expect(controller.canConfirm, isFalse);
      expect(repo.confirmCalls, ['person_1']);
      controller.dispose();
    });

    test('unlink / split / reassign correct a link (R6 undo path)', () async {
      final repo = FakePersonsRepository(
        persons: [
          fixturePersonDetail(
            id: 'person_1',
            name: 'Sam',
            linkState: LinkState.suggested,
            appearances: [
              fixtureAppearance(id: 'ap_1', personId: 'person_1'),
              fixtureAppearance(id: 'ap_2', personId: 'person_1'),
            ],
          ),
          fixturePersonDetail(
            id: 'person_2',
            name: 'Alex',
            linkState: LinkState.confirmed,
            appearances: const [],
          ),
        ],
      );
      final controller = PersonDetailController(
        personId: 'person_1',
        personsRepository: repo,
      );
      await controller.load();
      expect(controller.detail!.appearances.length, 2);

      // Split ap_2 onto a new person.
      final created = await controller.split(['ap_2']);
      expect(created, isNotNull);
      expect(created!.id, startsWith('person_split_'));
      expect(controller.detail!.appearances.map((a) => a.id), ['ap_1']);
      expect(repo.splitCalls.single.appearanceIds, ['ap_2']);

      // Reassign remaining ap_1 to person_2.
      await controller.reassign('ap_1', 'person_2');
      expect(controller.detail!.appearances, isEmpty);
      expect(repo.reassignCalls.single.personId, 'person_2');

      // Unlink from the new split person (visible undo path).
      final splitController = PersonDetailController(
        personId: created.id,
        personsRepository: repo,
      );
      await splitController.load();
      expect(splitController.detail!.appearances.single.id, 'ap_2');
      await splitController.unlink('ap_2');
      expect(splitController.detail!.appearances, isEmpty);
      expect(repo.unlinkCalls, ['ap_2']);

      controller.dispose();
      splitController.dispose();
    });

    test('rename updates displayed name', () async {
      final repo = FakePersonsRepository(
        persons: [fixturePersonDetail(id: 'person_1', name: 'Sam')],
      );
      final controller = PersonDetailController(
        personId: 'person_1',
        personsRepository: repo,
      );
      await controller.load();
      await controller.rename('Samantha');
      expect(controller.detail!.name, 'Samantha');
      expect(repo.renameCalls.single.name, 'Samantha');
      controller.dispose();
    });

    test('foreign person id surfaces error (R10)', () async {
      final repo = FakePersonsRepository(persons: const []);
      final controller = PersonDetailController(
        personId: 'foreign',
        personsRepository: repo,
      );
      await controller.load();
      expect(controller.phase, PersonDetailPhase.error);
      expect(controller.detail, isNull);
      controller.dispose();
    });
  });
}
