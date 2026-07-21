import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/review/knowledge_grouping.dart';

import 'fake_items_repository.dart';

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
}
