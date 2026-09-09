import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/auth/macos_oauth_deep_links.dart';

void main() {
  test('rotatingTokenNonce reads query and fragment', () {
    expect(
      rotatingTokenNonce(
        Uri.parse('tagkindesktop://oauth/callback?rotating_token_nonce=abc'),
      ),
      'abc',
    );
    expect(
      rotatingTokenNonce(
        Uri.parse('tagkindesktop://oauth/callback#rotating_token_nonce=def'),
      ),
      'def',
    );
    expect(
      rotatingTokenNonce(Uri.parse('tagkindesktop://oauth/callback')),
      isNull,
    );
  });

  test('live Allow during getInitialLink is not dropped', () async {
    final live = StreamController<Uri>.broadcast();
    final initial = Completer<Uri?>();
    final merged = mergeMacOsOauthDeepLinks(
      getInitialLink: () => initial.future,
      uriLinkStream: live.stream,
    );
    final received = <Uri?>[];
    final sub = merged.listen(received.add);

    live.add(
      Uri.parse('tagkindesktop://oauth/callback?rotating_token_nonce=live1'),
    );
    await Future<void>.delayed(Duration.zero);
    initial.complete(null);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single!.queryParameters[kRotatingTokenNonce], 'live1');

    await sub.cancel();
    await live.close();
  });

  test('duplicate nonce from initial + live is emitted once', () async {
    final url = Uri.parse(
      'tagkindesktop://oauth/callback?rotating_token_nonce=same',
    );
    final live = StreamController<Uri>.broadcast();
    final merged = mergeMacOsOauthDeepLinks(
      getInitialLink: () async => url,
      uriLinkStream: live.stream,
    );
    final received = <Uri?>[];
    final sub = merged.listen(received.add);

    live.add(url);
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));

    await sub.cancel();
    await live.close();
  });
}
