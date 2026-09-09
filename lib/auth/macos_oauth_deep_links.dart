import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// Custom URL scheme macOS routes OAuth callbacks back into the app through
/// (registered in `macos/Runner/Info.plist` `CFBundleURLTypes`).
const String kOauthRedirectScheme = 'tagkindesktop';

/// Query/fragment key Clerk puts on `tagkindesktop://oauth/callback`.
const String kRotatingTokenNonce = 'rotating_token_nonce';

/// Clerk rotating-token nonce on [uri], from the query or the fragment.
String? rotatingTokenNonce(Uri uri) {
  final query = uri.queryParameters[kRotatingTokenNonce];
  if (query != null && query.isNotEmpty) return query;
  final fragment = uri.fragment;
  if (fragment.isEmpty || !fragment.contains(kRotatingTokenNonce)) {
    return null;
  }
  final encoded = fragment.startsWith('/') ? fragment.substring(1) : fragment;
  final fromFragment = Uri.splitQueryString(encoded)[kRotatingTokenNonce];
  if (fromFragment == null || fromFragment.isEmpty) return null;
  return fromFragment;
}

void debugOauthDeepLink(Uri uri) {
  if (!kDebugMode) return;
  final hasNonce = rotatingTokenNonce(uri) != null;
  debugPrint(
    'macOS OAuth callback ${uri.scheme}://${uri.host}${uri.path}'
    '${hasNonce ? ' (has nonce)' : ' (missing nonce)'}',
  );
}

/// Safari Allow hops plus the process launch URL.
///
/// Subscribes to live links *before* `getInitialLink` so an Allow that
/// arrives during that method-channel round-trip is not stored as
/// `initialLink` with a nil event sink and then dropped. Duplicate nonces
/// (getInitialLink + uriLinkStream both emitting the launch URL) are ignored.
Stream<Uri?> macosOauthDeepLinks() {
  final links = AppLinks();
  return mergeMacOsOauthDeepLinks(
    getInitialLink: links.getInitialLink,
    uriLinkStream: links.uriLinkStream,
  );
}

/// Testable merge of the launch URL and later `tagkindesktop://` hops.
Stream<Uri?> mergeMacOsOauthDeepLinks({
  required Future<Uri?> Function() getInitialLink,
  required Stream<Uri> uriLinkStream,
}) {
  StreamSubscription<Uri>? sub;
  String? lastNonce;
  var closed = false;
  late final StreamController<Uri?> controller;

  void emit(Uri uri) {
    if (closed || controller.isClosed) return;
    final nonce = rotatingTokenNonce(uri);
    var outgoing = uri;
    if (nonce != null && uri.queryParameters[kRotatingTokenNonce] != nonce) {
      outgoing = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          kRotatingTokenNonce: nonce,
        },
      );
    }
    debugOauthDeepLink(outgoing);
    if (nonce != null && nonce == lastNonce) return;
    if (nonce != null) lastNonce = nonce;
    controller.add(outgoing);
  }

  controller = StreamController<Uri?>(
    onListen: () {
      // Live hops first so Allow during getInitialLink is not dropped.
      sub = uriLinkStream.listen(
        emit,
        onError: controller.addError,
      );
      getInitialLink()
          .then((uri) {
            if (uri != null) emit(uri);
          })
          .catchError((_) {});
    },
    onCancel: () async {
      closed = true;
      await sub?.cancel();
    },
  );

  return controller.stream;
}
