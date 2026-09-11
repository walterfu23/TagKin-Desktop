import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';

import 'fake_item_lists_repository.dart';

void main() {
  test('itemListToCsv writes header and current row order', () {
    final csv = itemListToCsv([
      fixtureEntry(
        itemId: 'photo-1',
        when: '2020-01-01T00:00:00.000Z',
        who: const ['Sam'],
        what: const ['swimming'],
      ),
      fixtureEntry(
        itemId: 'video-1',
        kind: ItemListEntryKind.keyperiod,
        keyPeriodId: 'kp-1',
        startMs: 1000,
        endMs: 4000,
        when: '2020-06-01T00:00:00.000Z',
        where: const ['park, beach'],
      ),
    ]);
    final lines = csv.trimRight().split(RegExp(r'\r?\n'));
    expect(
      lines.first,
      'kind,itemId,keyPeriodId,startMs,endMs,when,who,what,where',
    );
    expect(
      lines[1],
      'photo,photo-1,,,,2020-01-01T00:00:00.000Z,Sam,swimming,',
    );
    expect(lines[2], contains('keyPeriod,video-1,kp-1,1000,4000'));
    expect(lines[2], contains('"park, beach"'));
  });

  test('itemListEntryKindLabel uses canonical terms (R2)', () {
    expect(itemListEntryKindLabel(ItemListEntryKind.photo), 'Photo');
    expect(itemListEntryKindLabel(ItemListEntryKind.keyperiod), 'Key period');
  });

  test('formatKeyPeriodMs is m:ss', () {
    expect(formatKeyPeriodMs(0), '0:00');
    expect(formatKeyPeriodMs(65000), '1:05');
    expect(formatKeyPeriodMs(3600000), '1:00:00');
  });
}
