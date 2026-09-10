import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/item_detail_edits.dart';
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

  test('assignedPersonNames is unique A–Z case-insensitive; skips missing map',
      () {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 't1', dimension: 'who', value: 'toddler')],
      appearances: [
        fixtureAppearance(
          id: 'ap_b',
          personId: 'person_bea',
          itemId: 'item_1',
        ),
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
          id: 'ap_z',
          personId: 'person_zoe',
          itemId: 'item_1',
        ),
      ],
    );
    expect(
      assignedPersonNames(knowledge, {
        'person_alex': 'Alex',
        'person_bea': 'bea',
        'person_zoe': 'Zoe',
      }),
      ['Alex', 'bea', 'Zoe'],
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

  test('whoColumnValues fallback sorts who-tag values A–Z case-insensitive',
      () {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [
        fixtureTag(id: 't2', dimension: 'who', value: 'Sam'),
        fixtureTag(id: 't1', dimension: 'who', value: 'ada'),
      ],
    );
    expect(whoColumnValues(knowledge, const {}), ['ada', 'Sam']);
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

  test('whoOverlayPersonNames is assigned name, draft-aware', () {
    final item = fixtureItem(id: 'item_1');
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [
        fixtureTag(
          id: 'tag_who',
          dimension: 'who',
          value: 'toddler',
          region: const TagRegion(
            yMin: 0.1,
            xMin: 0.1,
            yMax: 0.4,
            xMax: 0.4,
          ),
        ),
      ],
      appearances: [
        fixtureAppearance(
          id: 'ap_1',
          personId: 'person_alex',
          itemId: 'item_1',
          tagId: 'tag_who',
        ),
      ],
    );
    const names = {'person_alex': 'Alex', 'person_maya': 'Maya'};

    expect(
      whoOverlayPersonNames(
        knowledge: knowledge,
        cropIntents: const {},
        personNamesById: names,
      ),
      {'tag_who': 'Alex'},
    );
    expect(
      whoOverlayPersonNames(
        knowledge: knowledge,
        cropIntents: const {
          'tag_who': PersonAssignIntent(name: 'Maya'),
        },
        personNamesById: names,
      ),
      {'tag_who': 'Maya'},
    );
    expect(
      whoOverlayPersonNames(
        knowledge: knowledge,
        cropIntents: const {
          'tag_who': PersonAssignIntent(unassign: true),
        },
        personNamesById: names,
      ),
      isEmpty,
    );
    expect(
      whoOverlayPersonNames(
        knowledge: knowledge,
        cropIntents: const {
          'tag_who': PersonAssignIntent(exclude: true),
        },
        personNamesById: names,
      ),
      isEmpty,
    );
  });

  test('draftPersonKeysOnItem occupies assigned and draft names', () {
    final item = fixtureItem(id: 'item_1');
    const region = TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4);
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [
        fixtureTag(
          id: 'tag_a',
          dimension: 'who',
          value: 'left',
          region: region,
        ),
        fixtureTag(
          id: 'tag_b',
          dimension: 'who',
          value: 'right',
          region: region,
        ),
      ],
      appearances: [
        fixtureAppearance(
          id: 'ap_a',
          personId: 'person_maya',
          itemId: 'item_1',
          tagId: 'tag_a',
        ),
        fixtureAppearance(
          id: 'ap_b',
          personId: null,
          itemId: 'item_1',
          tagId: 'tag_b',
        ),
      ],
    );
    const names = {'person_maya': 'Maya'};
    final occupied = draftPersonKeysOnItem(
      knowledge: knowledge,
      cropIntents: const {},
      appearanceIntents: const {},
      exclusionIntents: const {},
      pendingItemAssigns: const [],
      personNamesById: names,
      exceptTagId: 'tag_b',
    );
    expect(occupied.personIds, {'person_maya'});
    expect(occupied.nameKeys, {'maya'});
    expect(
      personOccupiedOnItem(
        occupied: occupied,
        personId: 'person_maya',
        personNamesById: names,
      ),
      isTrue,
    );
    expect(
      personOccupiedOnItem(
        occupied: occupied,
        personId: 'person_sam',
        personNamesById: const {'person_sam': 'Sam'},
      ),
      isFalse,
    );
  });

  test('groupDisplayTagsByDimension unions item-level and key-period values',
      () {
    final item = fixtureItem(id: 'item_v', type: ItemType.video);
    final knowledge = fixtureKnowledge(
      item: item,
      tags: [fixtureTag(id: 't_item', dimension: 'what', value: 'picnic')],
      keyPeriods: [
        KeyPeriodKnowledge(
          id: 'kp_1',
          itemId: item.id,
          startMs: 0,
          endMs: 2000,
          sampleTimestampMs: 500,
          tags: [
            fixtureTag(
              id: 't_period',
              itemId: item.id,
              keyPeriodId: 'kp_1',
              dimension: 'what',
              value: 'swimming',
            ),
            fixtureTag(
              id: 't_dup',
              itemId: item.id,
              keyPeriodId: 'kp_1',
              dimension: 'what',
              value: 'Picnic',
            ),
          ],
        ),
      ],
    );
    expect(
      groupDisplayTagsByDimension(knowledge)['what']!.map((t) => t.value),
      ['picnic', 'swimming'],
    );
  });

  test('whoFaceCropTags includes key-period who boxes', () {
    final item = fixtureItem(id: 'item_v', type: ItemType.video);
    const region = TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4);
    final knowledge = fixtureKnowledge(
      item: item,
      tags: const [],
      keyPeriods: [
        KeyPeriodKnowledge(
          id: 'kp_1',
          itemId: item.id,
          startMs: 0,
          endMs: 2000,
          sampleTimestampMs: 800,
          tags: [
            fixtureTag(
              id: 't_who',
              itemId: item.id,
              keyPeriodId: 'kp_1',
              dimension: 'who',
              value: 'Sam',
              region: region,
            ),
          ],
        ),
      ],
    );
    expect(whoFaceCropTags(knowledge).single.id, 't_who');
    expect(sampleTimestampMsForTagId(knowledge, 't_who'), 800);
  });

  test('draftPersonKeysOnItem occupancy is per key period on video', () {
    final item = fixtureItem(id: 'item_v', type: ItemType.video);
    const region = TagRegion(yMin: 0.1, xMin: 0.1, yMax: 0.4, xMax: 0.4);
    final knowledge = fixtureKnowledge(
      item: item,
      tags: const [],
      keyPeriods: [
        KeyPeriodKnowledge(
          id: 'kp_a',
          itemId: item.id,
          startMs: 0,
          endMs: 2000,
          sampleTimestampMs: 500,
          tags: [
            fixtureTag(
              id: 'tag_a',
              itemId: item.id,
              keyPeriodId: 'kp_a',
              dimension: 'who',
              value: 'left',
              region: region,
            ),
          ],
        ),
        KeyPeriodKnowledge(
          id: 'kp_b',
          itemId: item.id,
          startMs: 2000,
          endMs: 4000,
          sampleTimestampMs: 3000,
          tags: [
            fixtureTag(
              id: 'tag_b',
              itemId: item.id,
              keyPeriodId: 'kp_b',
              dimension: 'who',
              value: 'right',
              region: region,
            ),
          ],
        ),
      ],
      appearances: [
        fixtureAppearance(
          id: 'ap_a',
          personId: 'person_maya',
          itemId: item.id,
          tagId: 'tag_a',
        ),
        fixtureAppearance(
          id: 'ap_b',
          personId: 'person_maya',
          itemId: item.id,
          tagId: 'tag_b',
        ),
      ],
    );
    const names = {'person_maya': 'Maya'};
    final occupiedA = draftPersonKeysOnItem(
      knowledge: knowledge,
      cropIntents: const {},
      appearanceIntents: const {},
      exclusionIntents: const {},
      pendingItemAssigns: const [],
      personNamesById: names,
      exceptTagId: 'tag_b',
      sameKeyPeriodId: 'kp_b',
    );
    expect(occupiedA.personIds, isEmpty);
    final occupiedB = draftPersonKeysOnItem(
      knowledge: knowledge,
      cropIntents: const {},
      appearanceIntents: const {},
      exclusionIntents: const {},
      pendingItemAssigns: const [],
      personNamesById: names,
      exceptTagId: 'tag_a',
      sameKeyPeriodId: 'kp_a',
    );
    expect(occupiedB.personIds, isEmpty);
    final occupiedSame = draftPersonKeysOnItem(
      knowledge: knowledge,
      cropIntents: const {},
      appearanceIntents: const {},
      exclusionIntents: const {},
      pendingItemAssigns: const [],
      personNamesById: names,
      sameKeyPeriodId: 'kp_a',
    );
    expect(occupiedSame.personIds, {'person_maya'});
  });
}
