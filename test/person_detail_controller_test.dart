import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/persons/person_detail_controller.dart';

import 'fake_persons_repository.dart';

void main() {
  group('PersonDetailController', () {
    test('load populates detail', () async {
      final repo = FakePersonsRepository(
        persons: [
          fixturePersonDetail(id: 'person_1', name: 'Sam'),
        ],
      );
      final controller = PersonDetailController(
        personId: 'person_1',
        personsRepository: repo,
      );

      await controller.load();
      expect(controller.phase, PersonDetailPhase.ready);
      expect(controller.detail!.name, 'Sam');
      controller.dispose();
    });

    test('unassign / reassign (incl. new person) correct a link (R6)', () async {
      final repo = FakePersonsRepository(
        persons: [
          fixturePersonDetail(
            id: 'person_1',
            name: 'Sam',
            appearances: [
              fixtureAppearance(id: 'ap_1', personId: 'person_1'),
              fixtureAppearance(id: 'ap_2', personId: 'person_1'),
            ],
          ),
          fixturePersonDetail(
            id: 'person_2',
            name: 'Alex',
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

      // Reassign ap_2 onto a brand-new named person.
      await controller.reassign('ap_2', name: 'Riley');
      expect(controller.detail!.appearances.map((a) => a.id), ['ap_1']);
      expect(repo.reassignCalls.single.appearanceId, 'ap_2');
      expect(repo.reassignCalls.single.personId, isNull);
      expect(repo.reassignCalls.single.name, 'Riley');

      // Reassign remaining ap_1 to person_2.
      await controller.reassign('ap_1', personId: 'person_2');
      expect(controller.detail!.appearances, isEmpty);
      expect(repo.reassignCalls.last.personId, 'person_2');

      // Unassign from the new person (visible undo path).
      final newPersonId = (await repo.listPersons())
          .firstWhere((p) => p.id.startsWith('person_new_'))
          .id;
      final newController = PersonDetailController(
        personId: newPersonId,
        personsRepository: repo,
      );
      await newController.load();
      expect(newController.detail!.appearances.single.id, 'ap_2');
      await newController.unlink('ap_2');
      expect(newController.detail!.appearances, isEmpty);
      expect(repo.unlinkCalls, ['ap_2']);

      controller.dispose();
      newController.dispose();
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

    test('unassignPerson dissolves person via deletePerson API', () async {
      final repo = FakePersonsRepository(
        persons: [
          fixturePersonDetail(id: 'person_1', name: 'Sam'),
        ],
      );
      final controller = PersonDetailController(
        personId: 'person_1',
        personsRepository: repo,
      );
      await controller.load();
      expect(controller.canUnassign, isTrue);
      final ok = await controller.unassignPerson();
      expect(ok, isTrue);
      expect(repo.deleteCalls, ['person_1']);
      controller.dispose();
    });

    test('canUnassign is false while busy or before detail loads', () async {
      final repo = FakePersonsRepository(
        persons: [fixturePersonDetail(id: 'person_1', name: 'Sam')],
      );
      final controller = PersonDetailController(
        personId: 'person_1',
        personsRepository: repo,
      );
      expect(controller.canUnassign, isFalse);
      await controller.load();
      expect(controller.canUnassign, isTrue);
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
