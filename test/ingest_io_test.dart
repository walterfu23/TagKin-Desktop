import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/ingest/ingest_io.dart';

import 'fake_items_repository.dart';

void main() {
  test('listItemsWithRetry recovers from one connection-closed error', () async {
    var calls = 0;
    final repo = FakeItemsRepository(
      onListItems: () async {
        calls++;
        if (calls == 1) {
          throw http.ClientException(
            'Connection closed before full header was received',
            Uri.parse('http://localhost:8787/items'),
          );
        }
      },
    );
    final items = await listItemsWithRetry(
      repo,
      delay: Duration.zero,
    );
    expect(calls, 2);
    expect(items, isEmpty);
  });
}
