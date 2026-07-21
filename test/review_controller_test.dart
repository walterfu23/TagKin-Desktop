import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';
import 'package:tagkin_desktop/review/review_controller.dart';

import 'fake_comments_repository.dart';
import 'fake_corrections_repository.dart';
import 'fake_items_repository.dart';

ReviewController _controller({
  required FakeItemsRepository items,
  FakeCorrectionsRepository? corrections,
  FakeCommentsRepository? comments,
  String itemId = 'item_1',
}) {
  return ReviewController(
    itemId: itemId,
    itemsRepository: items,
    correctionsRepository:
        corrections ?? FakeCorrectionsRepository(items: items),
    commentsRepository: comments ?? FakeCommentsRepository(),
    resolveMedia: (_) async =>
        const LocalMediaResolution(status: LocalMediaStatus.missing),
  );
}

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
      correctionsRepository: FakeCorrectionsRepository(items: items),
      commentsRepository: FakeCommentsRepository(),
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
    final controller = _controller(items: items, itemId: 'foreign');
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

    final fromA = _controller(items: repoA, itemId: 'item_a');
    await fromA.load();
    expect(fromA.knowledge!.tags.single.value, 'secret-a');

    final fromB = _controller(items: repoB, itemId: 'item_a');
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
    final controller = _controller(items: items);
    final phases = <ReviewPhase>[];
    controller.addListener(() => phases.add(controller.phase));
    await controller.load();
    expect(phases, contains(ReviewPhase.loading));
    expect(phases, contains(ReviewPhase.ready));
    controller.dispose();
  });

  test('addTag optimistic then reconciles approved value; undo restores',
      () async {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 'tag_what', dimension: 'what', value: 'picnic')],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final corrections = FakeCorrectionsRepository(items: items);
    final controller = _controller(items: items, corrections: corrections);
    await controller.load();

    final beforeValues =
        controller.knowledge!.tags.map((t) => t.value).toList();
    expect(beforeValues, contains('picnic'));

    // Start addTag without awaiting so we can observe optimistic state.
    final pending = controller.addTag(dimension: 'where', value: 'beach');
    // Allow microtask for optimistic notify.
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.knowledge!.tags.any((t) => t.value == 'beach'),
      isTrue,
      reason: 'optimistic tag visible before reconcile',
    );
    await pending;
    expect(controller.phase, ReviewPhase.ready);
    expect(
      controller.knowledge!.tags.any((t) => t.value == 'beach'),
      isTrue,
    );
    expect(corrections.addTagCalls, hasLength(1));
    expect(controller.knowledge!.corrections, isNotEmpty);

    final correctionId = controller.knowledge!.corrections.last.id;
    await controller.undoCorrection(correctionId);
    expect(corrections.undoCalls, [correctionId]);
    expect(
      controller.knowledge!.corrections.any((c) => c.id == correctionId),
      isFalse,
    );
    controller.dispose();
  });

  test('editTag updates displayed value after reconcile', () async {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 'tag_what', dimension: 'what', value: 'picnic')],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final corrections = FakeCorrectionsRepository(items: items);
    final controller = _controller(items: items, corrections: corrections);
    await controller.load();
    await controller.editTag('tag_what', 'hiking');
    expect(
      controller.knowledge!.tags.any((t) => t.value == 'hiking'),
      isTrue,
    );
    expect(corrections.editTagCalls.single.input.value, 'hiking');
    controller.dispose();
  });

  test('removeTag drops tag from approved projection', () async {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 'tag_what', dimension: 'what', value: 'picnic')],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final corrections = FakeCorrectionsRepository(items: items);
    final controller = _controller(items: items, corrections: corrections);
    await controller.load();
    await controller.removeTag('tag_what');
    expect(controller.knowledge!.tags, isEmpty);
    expect(corrections.removeTagCalls, ['tag_what']);
    controller.dispose();
  });

  test('correctCapturedAt updates item.capturedAt', () async {
    final item = fixtureItem(id: 'item_1', capturedAt: '2026-01-01T00:00:00.000Z');
    final knowledge = fixtureKnowledge(item: item, tags: const []);
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final corrections = FakeCorrectionsRepository(items: items);
    final controller = _controller(items: items, corrections: corrections);
    await controller.load();
    await controller.correctCapturedAt('2026-07-04T15:00:00.000Z');
    expect(controller.knowledge!.item.capturedAt, '2026-07-04T15:00:00.000Z');
    controller.dispose();
  });

  test('addItemComment attaches with server author + timestamp (R10)',
      () async {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(item: item, tags: const []);
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final comments = FakeCommentsRepository(authorUserId: 'acc_server');
    final controller = _controller(items: items, comments: comments);
    await controller.load();
    await controller.addItemComment('nice shot');
    expect(controller.itemComments, hasLength(1));
    final c = controller.itemComments.single;
    expect(c.body, 'nice shot');
    expect(c.authorUserId, 'acc_server');
    expect(c.createdAt, isNotEmpty);
    expect(c.authorUserId, isNot(equals('pending')));
    expect(comments.createItemCalls.single.input.body, 'nice shot');
    controller.dispose();
  });

  test('mutation failure rolls back optimistic tag (R6)', () async {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 'tag_what', value: 'picnic')],
    );
    final items = FakeItemsRepository(
      items: [item],
      knowledgeByItemId: {'item_1': knowledge},
    );
    final corrections = FakeCorrectionsRepository(items: items)
      ..addTagError = ApiException(statusCode: 500, message: 'boom');
    final controller = _controller(items: items, corrections: corrections);
    await controller.load();
    await controller.addTag(dimension: 'where', value: 'fail');
    expect(
      controller.knowledge!.tags.any((t) => t.value == 'fail'),
      isFalse,
    );
    expect(controller.mutationError, isA<ApiException>());
    controller.dispose();
  });
}
