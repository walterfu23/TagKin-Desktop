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

    test('unassign / reassign (incl. new person) correct a link (R6)', () async {
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

      // Reassign ap_2 onto a new person.
      await controller.reassign('ap_2', null);
      expect(controller.detail!.appearances.map((a) => a.id), ['ap_1']);
      expect(repo.reassignCalls.single.appearanceId, 'ap_2');
      expect(repo.reassignCalls.single.personId, isNull);

      // Reassign remaining ap_1 to person_2.
      await controller.reassign('ap_1', 'person_2');
      expect(controller.detail!.appearances, isEmpty);
      expect(repo.reassignCalls.last.personId, 'person_2');

      // Unassign from the new person (visible undo path).
      final newPersonId = repo.reassignCalls.first.personId == null
          ? (await repo.listPersons())
              .firstWhere((p) => p.id.startsWith('person_new_'))
              .id
          : null;
      expect(newPersonId, isNotNull);
      final newController = PersonDetailController(
        personId: newPersonId!,
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

    test('delete removes suggested person', () async {
      final repo = FakePersonsRepository(
        persons: [
          fixturePersonDetail(
            id: 'person_1',
            name: null,
            linkState: LinkState.suggested,
          ),
        ],
      );
      final controller = PersonDetailController(
        personId: 'person_1',
        personsRepository: repo,
      );
      await controller.load();
      expect(controller.canDelete, isTrue);
      final ok = await controller.delete();
      expect(ok, isTrue);
      expect(repo.deleteCalls, ['person_1']);
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
