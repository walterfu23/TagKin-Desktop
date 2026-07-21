import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/review/review_controller.dart';

import 'fake_items_repository.dart';

void main() {
  test('load fetches knowledge and resolves local media', () async {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(item: item);
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    LocalMediaResolution? seen;
    final controller = ReviewController(
      itemId: 'item_1',
      itemsRepository: items,
      resolveMedia: (i) async {
        seen = const LocalMediaResolution(status: LocalMediaStatus.missing);
        return seen!;
      },
    );
    await controller.load();
    expect(controller.phase, ReviewPhase.ready);
    expect(controller.knowledge!.tags.length, 4);
    expect(seen, isNotNull);
    expect(controller.media!.status, LocalMediaStatus.missing);
    controller.dispose();
  });

  test('foreign knowledge 404 surfaces as error (R10)', () async {
    final items = FakeItemsRepository(
      getKnowledgeError: ApiException(statusCode: 404, message: 'Not found'),
    );
    final controller = ReviewController(
      itemId: 'foreign',
      itemsRepository: items,
      resolveMedia: (_) async =>
          const LocalMediaResolution(status: LocalMediaStatus.missing),
    );
    await controller.load();
    expect(controller.phase, ReviewPhase.error);
    expect(controller.error, isA<ApiException>());
    controller.dispose();
  });

  test('second account cannot observe first account knowledge (R10)', () async {
    final aItem = fixtureItem(id: 'item_a');
    final aKnowledge = fixtureKnowledge(
      item: aItem,
      tags: [fixtureTag(id: 't_a', value: 'secret-a')],
    );
    final repoA = FakeItemsRepository(
      items: [aItem],
      knowledgeByItemId: {'item_a': aKnowledge},
    );
    final repoB = FakeItemsRepository(
      getKnowledgeError: ApiException(statusCode: 404, message: 'Not found'),
    );

    final fromA = ReviewController(
      itemId: 'item_a',
      itemsRepository: repoA,
      resolveMedia: (_) async =>
          const LocalMediaResolution(status: LocalMediaStatus.missing),
    );
    await fromA.load();
    expect(fromA.knowledge!.tags.single.value, 'secret-a');

    final fromB = ReviewController(
      itemId: 'item_a',
      itemsRepository: repoB,
      resolveMedia: (_) async =>
          const LocalMediaResolution(status: LocalMediaStatus.missing),
    );
    await fromB.load();
    expect(fromB.phase, ReviewPhase.error);
    expect(fromB.knowledge, isNull);

    fromA.dispose();
    fromB.dispose();
  });

  test('load notifies listeners', () async {
    final item = fixtureItem();
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': fixtureKnowledge(item: item)},
    );
    final controller = ReviewController(
      itemId: 'item_1',
      itemsRepository: items,
      resolveMedia: (_) async =>
          const LocalMediaResolution(status: LocalMediaStatus.missing),
    );
    final phases = <ReviewPhase>[];
    controller.addListener(() => phases.add(controller.phase));
    await controller.load();
    expect(phases, contains(ReviewPhase.loading));
    expect(phases, contains(ReviewPhase.ready));
    controller.dispose();
  });
}
