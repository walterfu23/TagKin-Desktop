import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';

import 'fake_items_repository.dart';
import 'fake_persons_repository.dart';

void main() {
  test('groupItemLevelTagsByDimension buckets who/what/when/where', () {
    final tags = [
      fixtureTag(id: '1', dimension: 'who', value: 'Sam'),
      fixtureTag(id: '2', dimension: 'what', value: 'picnic'),
      fixtureTag(id: '3', dimension: 'when', value: '2026-07-01'),
      fixtureTag(id: '4', dimension: 'where', value: 'park'),
      fixtureTag(
        id: '5',
        dimension: 'what',
        value: 'ignored-key-period',
        keyPeriodId: 'kp_1',
      ),
      fixtureTag(
        id: '6',
        dimension: 'what',
        value: 'removed',
        status: TagStatus.removed,
      ),
    ];
    final grouped = groupItemLevelTagsByDimension(tags);
    expect(grouped['who']!.single.value, 'Sam');
    expect(grouped['what']!.single.value, 'picnic');
    expect(grouped['when']!.single.value, '2026-07-01');
    expect(grouped['where']!.single.value, 'park');
  });

  test('provenanceLabel includes source provider model confidence', () {
    final tag = fixtureTag(
      source: KnowledgeSource.model,
      provider: 'stub',
      modelId: 'flash',
      confidence: 0.91,
    );
    expect(provenanceLabel(tag), 'model · stub · flash · 91%');
  });

  test('assignedPersonNames is unique in first-seen order; skips missing map',
      () {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 't1', dimension: 'who', value: 'toddler')],
      appearances: [
        fixtureAppearance(
          id: 'ap_a',
          personId: 'person_alex',
          itemId: 'item_1',
          tagId: 't1',
        ),
        fixtureAppearance(
          id: 'ap_a2',
          personId: 'person_alex',
          itemId: 'item_1',
          tagId: 't1',
        ),
        fixtureAppearance(
          id: 'ap_missing',
          personId: 'person_gone',
          itemId: 'item_1',
        ),
        fixtureAppearance(
          id: 'ap_b',
          personId: 'person_bea',
          itemId: 'item_1',
        ),
      ],
    );
    expect(
      assignedPersonNames(knowledge, {
        'person_alex': 'Alex',
        'person_bea': 'Bea',
      }),
      ['Alex', 'Bea'],
    );
  });

  test('whoColumnValues uses names when any assigned appearance resolves', () {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 't1', dimension: 'who', value: 'toddler')],
      appearances: [
        fixtureAppearance(
          id: 'ap_1',
          personId: 'person_alex',
          itemId: 'item_1',
          tagId: 't1',
        ),
      ],
    );
    expect(
      whoColumnValues(knowledge, {'person_alex': 'Alex'}),
      ['Alex'],
    );
  });

  test('whoColumnValues falls back to who-tag values when no names resolve',
      () {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 't1', dimension: 'who', value: 'toddler')],
      appearances: [
        fixtureAppearance(
          id: 'ap_unlinked',
          personId: null,
          itemId: 'item_1',
          tagId: 't1',
        ),
      ],
    );
    expect(whoColumnValues(knowledge, const {}), ['toddler']);
  });

  test('knowledgeCsvValues who is names then tag values', () {
    expect(
      knowledgeCsvValues(
        dimension: 'who',
        tags: [fixtureTag(id: 't1', dimension: 'who', value: 'toddler')],
        personNames: ['Alex'],
      ),
      ['Alex', 'toddler'],
    );
    expect(
      knowledgeCsvValues(
        dimension: 'what',
        tags: [fixtureTag(id: 't2', dimension: 'what', value: 'picnic')],
      ),
      ['picnic'],
    );
    expect(
      knowledgeCsvValues(
        dimension: 'when',
        tags: [
          fixtureTag(
            id: 't3',
            dimension: 'when',
            value: '2026-07-01T12:00:00.000Z',
          ),
        ],
      ),
      ['2026-07-01T12:00:00.000Z'],
    );
    expect(
      knowledgeCsvValues(
        dimension: 'when',
        tags: [fixtureTag(id: 't4', dimension: 'when', value: '2026-07-01')],
      ),
      ['2026-07-01'],
    );
  });

  test('itemHasWhoFaceCrops is true only with who region', () {
    final item = fixtureItem(id: 'item_1');
    expect(
      itemHasWhoFaceCrops(
        fixtureKnowledge(
          item: item,
          tags: [fixtureTag(id: 't1', dimension: 'who', value: 'toddler')],
        ),
      ),
      isFalse,
    );
    expect(
      itemHasWhoFaceCrops(
        fixtureKnowledge(
          item: item,
          tags: [
            fixtureTag(
              id: 't1',
              dimension: 'who',
              value: 'toddler',
              region: const TagRegion(
                yMin: 0.1,
                xMin: 0.1,
                yMax: 0.2,
                xMax: 0.2,
              ),
            ),
          ],
        ),
      ),
      isTrue,
    );
  });

  test('itemLevelPersonAssignments skips tagged crops', () {
    final knowledge = fixtureKnowledge(
      item: fixtureItem(id: 'item_1'),
      appearances: [
        fixtureAppearance(
          id: 'ap_item',
          personId: 'p1',
          tagId: null,
        ),
        fixtureAppearance(
          id: 'ap_crop',
          personId: 'p1',
          tagId: 'tag_who',
        ),
      ],
    );
    expect(
      itemLevelPersonAssignments(knowledge).map((a) => a.id),
      ['ap_item'],
    );
  });
}
