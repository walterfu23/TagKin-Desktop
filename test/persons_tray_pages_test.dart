import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';

import 'fake_persons_repository.dart';

void main() {
  test('listAllUnassignedAppearances walks past the first 500-row page',
      () async {
    final repo = FakePersonsRepository();
    for (var i = 0; i < 501; i++) {
      repo.unassignedAppearances.add(
        fixtureAppearance(
          id: 'ap_$i',
          personId: null,
          tagId: 'tag_$i',
          assignmentState: null,
        ),
      );
    }
    final all = await repo.listAllUnassignedAppearances();
    expect(all, hasLength(501));
    final found = await repo.findUnassignedAppearanceByTagId('tag_500');
    expect(found?.id, 'ap_500');
  });
}
