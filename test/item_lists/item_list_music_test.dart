import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/item_lists/item_list_music.dart';

void main() {
  test('estimate POSTs durationMs only (R1/R10)', () async {
    final mock = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/music/estimate');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys, ['durationMs']);
      expect(body.containsKey('ownerUserId'), isFalse);
      expect(body.containsKey('provider'), isFalse);
      return http.Response(
        jsonEncode({'creditsUsed': 4}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = ApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () => 'tok',
      httpClient: mock,
    );
    final result = await MusicRepository(client).estimate(durationMs: 10000);
    expect(result.creditsUsed, 4);
    client.close();
  });

  test('generate POSTs durationMs and prompt; response has no vendor (R8)',
      () async {
    final mock = MockClient((request) async {
      expect(request.url.path, '/music/generate');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys.toSet(), {'durationMs', 'prompt'});
      expect(body.containsKey('ownerUserId'), isFalse);
      return http.Response(
        jsonEncode({
          'audioBase64': base64Encode([1, 2, 3]),
          'mimeType': 'audio/wav',
          'generatedMs': 4000,
          'creditsUsed': 0,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final client = ApiClient(
      baseUrl: 'http://api.test',
      tokenProvider: () => 'tok',
      httpClient: mock,
    );
    final result = await MusicRepository(client).generate(
      durationMs: 4000,
      prompt: 'quiet piano',
    );
    expect(result.mimeType, 'audio/wav');
    expect(result.generatedMs, 4000);
    expect(result.creditsUsed, 0);
    client.close();
  });
}
