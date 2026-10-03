import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class GoogleLoopbackException implements Exception {
  GoogleLoopbackException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One-shot `http://127.0.0.1:<port>` listener that receives Google's OAuth
/// redirect (RFC 8252 loopback flow). Works the same on macOS and Windows: no
/// URL-scheme registration and no single-instance link forwarding.
class GoogleLoopback {
  GoogleLoopback._(
    this._server,
    this.state,
    this._timeout,
    this.redirectUri,
  ) {
    // The page awaits [code]; avoid an unhandled-error report if it is
    // cancelled before anything listens.
    _done.future.ignore();
    _sub = _server.listen(_onRequest);
    _timer = Timer(_timeout, () {
      _fail(GoogleLoopbackException(
        'Google sign-in timed out. Try again.',
      ));
    });
  }

  static Future<GoogleLoopback> start({
    Duration timeout = const Duration(minutes: 3),
    Random? random,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final rng = random ?? Random.secure();
    final state = base64Url
        .encode(List<int>.generate(16, (_) => rng.nextInt(256)))
        .replaceAll('=', '');
    return GoogleLoopback._(
      server,
      state,
      timeout,
      'http://127.0.0.1:${server.port}',
    );
  }

  final HttpServer _server;
  final Duration _timeout;
  final String state;
  final String redirectUri;
  final _done = Completer<String>();
  late final StreamSubscription<HttpRequest> _sub;
  Timer? _timer;
  var _closed = false;

  /// Completes with the authorization code, or errors (denied, timeout, cancel).
  Future<String> get code => _done.future;

  Future<void> cancel() async {
    _fail(GoogleLoopbackException('Google sign-in was cancelled.'));
  }

  Future<void> _onRequest(HttpRequest request) async {
    final params = request.uri.queryParameters;
    // Browsers also hit /favicon.ico; only the redirect carries code or error.
    final isRedirect =
        params.containsKey('code') || params.containsKey('error');
    if (!isRedirect) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    if (params['state'] != state) {
      await _reply(request, 'This sign-in link is not valid for TagKin.',
          status: HttpStatus.badRequest);
      return;
    }
    final error = params['error'];
    final code = params['code'];
    if (error != null) {
      await _reply(request, 'Google sign-in was cancelled. You can close this tab.');
      _fail(GoogleLoopbackException(
        error == 'access_denied'
            ? 'Google sign-in was cancelled.'
            : 'Google sign-in failed ($error).',
      ));
      return;
    }
    if (code == null || code.isEmpty) {
      await _reply(request, 'Google did not return a sign-in code.',
          status: HttpStatus.badRequest);
      return;
    }
    await _reply(
      request,
      'Return to TagKin to finish signing in. You can close this tab.',
    );
    if (!_done.isCompleted) _done.complete(code);
    // After this handler returns. Cancelling the subscription from inside
    // its own callback deadlocks the close.
    scheduleMicrotask(_close);
  }

  Future<void> _reply(
    HttpRequest request,
    String message, {
    int status = HttpStatus.ok,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.html;
    final safe = const HtmlEscape().convert(message);
    request.response.write(
      '<!doctype html><html><head><meta charset="utf-8"><title>TagKin</title></head>'
      '<body style="font-family:-apple-system,Segoe UI,sans-serif;text-align:center;margin-top:20vh">'
      '<p>$safe</p></body></html>',
    );
    await request.response.close();
  }

  void _fail(Object error) {
    if (!_done.isCompleted) _done.completeError(error);
    scheduleMicrotask(_close);
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    _timer?.cancel();
    await _sub.cancel();
    await _server.close(force: true);
  }
}
