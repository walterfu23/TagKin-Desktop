import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';
import 'package:tagkin_desktop/auth/firebase_identity.dart';
import 'package:url_launcher/url_launcher.dart';

const _toolkit = 'https://identitytoolkit.googleapis.com';

/// Enterprise action for adding a phone.
const String kMfaSmsEnrollAction = 'mfaSmsEnrollment';

/// Enterprise action for a text at sign-in.
const String kMfaSmsSignInAction = 'mfaSmsSignIn';

/// Opens the check on `127.0.0.1`. Phone checks solved on `localhost` are rejected.
Future<TextCheck> solveRecaptcha({
  required FirebasePublicConfig config,
  required String action,
  http.Client? httpClient,
}) async {
  final setup = await recaptchaSetup(config, httpClient: httpClient);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final done = Completer<String>();
  server.listen((request) async {
    final page = setup.enterprise
        ? _enterprisePage(setup.siteKey, action)
        : _classicPage(setup.siteKey);
    if (request.uri.path == '/done' && request.method == 'POST') {
      final body = await utf8.decodeStream(request);
      final token = recaptchaFormToken(body);
      request.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write(token == null ? page : '<p>Return to FamFace.</p>');
      await request.response.close();
      if (token != null && !done.isCompleted) {
        done.complete(token);
      }
      return;
    }
    request.response
      ..statusCode = 200
      ..headers.contentType = ContentType.html
      ..write(page);
    await request.response.close();
  });
  try {
    final opened = await launchUrl(
      Uri.parse('http://127.0.0.1:${server.port}/'),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      throw FirebaseAuthException('Could not open the browser to send a text.');
    }
    final token = await done.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => throw FirebaseAuthException(
        'The text message check timed out. Try again.',
      ),
    );
    return TextCheck(token: token, enterprise: setup.enterprise);
  } finally {
    await server.close(force: true);
  }
}

const _textCheckFailed = 'Could not start the text message check.';

class RecaptchaSetup {
  const RecaptchaSetup({required this.siteKey, required this.enterprise});

  final String siteKey;
  final bool enterprise;
}

class TextCheck {
  const TextCheck({required this.token, required this.enterprise});

  final String token;
  final bool enterprise;
}

/// An Enterprise token uses captchaResponse. A classic checkbox token is
/// recaptchaToken, with captchaResponse set to NO_RECAPTCHA.
Map<String, String> smsDispatchFields(
  String token, {
  required bool enterprise,
}) {
  if (enterprise) {
    return {
      'captchaResponse': token,
      'clientType': 'CLIENT_TYPE_WEB',
      'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
    };
  }
  return {
    'recaptchaToken': token,
    'captchaResponse': 'NO_RECAPTCHA',
    'clientType': 'CLIENT_TYPE_WEB',
    'recaptchaVersion': 'RECAPTCHA_ENTERPRISE',
  };
}

/// Loads an Enterprise key when Firebase has one, otherwise the classic key.
Future<RecaptchaSetup> recaptchaSetup(
  FirebasePublicConfig config, {
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final enterprise = await _optionalKey(
      client,
      '$_toolkit/v2/recaptchaConfig?key=${Uri.encodeQueryComponent(config.apiKey)}'
      '&clientType=CLIENT_TYPE_WEB&version=RECAPTCHA_ENTERPRISE',
      'recaptchaKey',
    );
    if (enterprise != null) {
      return RecaptchaSetup(siteKey: enterprise, enterprise: true);
    }
    final classic = await _optionalKey(
      client,
      '$_toolkit/v1/recaptchaParams?key=${Uri.encodeQueryComponent(config.apiKey)}',
      'recaptchaSiteKey',
    );
    if (classic == null) throw FirebaseAuthException(_textCheckFailed);
    return RecaptchaSetup(siteKey: classic, enterprise: false);
  } finally {
    if (close) client.close();
  }
}

Future<String?> _optionalKey(http.Client client, String url, String field) async {
  try {
    final res = await client.get(Uri.parse(url));
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    final body = res.body.trimLeft();
    if (!body.startsWith('{')) return null;
    final json = jsonDecode(body);
    final key = json is Map ? json[field] : null;
    if (key is! String || key.isEmpty) return null;
    return key;
  } on FormatException {
    return null;
  }
}

/// The token posted by the localhost page. A plus sign stays a plus sign.
String? recaptchaFormToken(String body) {
  final fields = _formFields(body);
  final token = fields['g-recaptcha-response'] ?? fields['token'];
  if (token == null || token.isEmpty) return null;
  return token;
}

Map<String, String> _formFields(String body) {
  final fields = <String, String>{};
  for (final part in body.split('&')) {
    if (part.isEmpty) continue;
    final splitAt = part.indexOf('=');
    final rawKey = splitAt < 0 ? part : part.substring(0, splitAt);
    final rawValue = splitAt < 0 ? '' : part.substring(splitAt + 1);
    fields[_decodeForm(rawKey)] = _decodeForm(rawValue);
  }
  return fields;
}

String _decodeForm(String value) {
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

String _enterprisePage(String siteKey, String action) {
  final src = Uri.encodeComponent(siteKey);
  final jsKey = jsonEncode(siteKey);
  final jsAction = jsonEncode(action);
  return '''
<!doctype html>
<meta charset="utf-8">
<title>FamFace</title>
<p>Confirming the text message check. Return to FamFace when this page says to.</p>
<script src="https://www.google.com/recaptcha/enterprise.js?render=$src"></script>
<script>
grecaptcha.enterprise.ready(function () {
  grecaptcha.enterprise.execute($jsKey, {action: $jsAction}).then(function (token) {
    fetch('/done', {
      method: 'POST',
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: 'token=' + encodeURIComponent(token)
    }).then(function (response) { return response.text(); })
      .then(function (html) { document.body.innerHTML = html; });
  }).catch(function () {
    var note = document.createElement('p');
    note.textContent = 'The text message check was rejected. Close this page and try again.';
    document.body.appendChild(note);
  });
});
</script>
''';
}

String _classicPage(String siteKey) {
  final key = const HtmlEscape().convert(siteKey);
  return '''
<!doctype html>
<meta charset="utf-8">
<title>FamFace</title>
<p>Check the box, press Continue, then return to FamFace.</p>
<script src="https://www.google.com/recaptcha/api.js" async defer></script>
<form method="POST" action="/done">
  <div class="g-recaptcha" data-sitekey="$key"></div>
  <p><button type="submit">Continue</button></p>
</form>
''';
}

/// Sends the SMS for an enrolled phone and returns the session info.
Future<String> startSmsSignIn({
  required FirebasePublicConfig config,
  required MfaChallenge challenge,
  required MfaFactor factor,
  required String recaptchaToken,
  required bool enterprise,
  http.Client? httpClient,
}) async {
  final json = await _post(
    config,
    '/v2/accounts/mfaSignIn:start',
    {
      'mfaPendingCredential': challenge.pendingCredential,
      'mfaEnrollmentId': factor.enrollmentId,
      'phoneSignInInfo': smsDispatchFields(
        recaptchaToken,
        enterprise: enterprise,
      ),
    },
    httpClient: httpClient,
  );
  final info = json['phoneResponseInfo'];
  final session = info is Map ? info['sessionInfo'] : null;
  if (session is! String || session.isEmpty) {
    throw FirebaseAuthException('Could not send the text.');
  }
  return session;
}

Future<FirebaseSession> finishMfaSignIn({
  required FirebasePublicConfig config,
  required MfaChallenge challenge,
  required MfaFactor factor,
  required String code,
  String? smsSessionInfo,
  http.Client? httpClient,
}) async {
  final body = <String, Object?>{
    'mfaPendingCredential': challenge.pendingCredential,
  };
  if (factor.kind == 'totp') {
    // mfaEnrollmentId is a sibling of totpVerificationInfo. Nesting it makes
    // Firebase reject the request as an invalid argument.
    body['mfaEnrollmentId'] = factor.enrollmentId;
    body['totpVerificationInfo'] = {'verificationCode': code.trim()};
  } else {
    final session = smsSessionInfo;
    if (session == null || session.isEmpty) {
      throw FirebaseAuthException('Send the text before entering the code.');
    }
    body['phoneVerificationInfo'] = {
      'sessionInfo': session,
      'code': code.trim(),
    };
  }
  final json = await _post(
    config,
    '/v2/accounts/mfaSignIn:finalize',
    body,
    httpClient: httpClient,
  );
  return _session(json);
}

class TotpEnrollment {
  const TotpEnrollment({
    required this.sessionInfo,
    required this.sharedSecretKey,
    required this.otpauthUrl,
  });

  final String sessionInfo;
  final String sharedSecretKey;
  final String otpauthUrl;
}

Future<TotpEnrollment> startTotpEnrollment({
  required FirebasePublicConfig config,
  required String idToken,
  required String accountLabel,
  http.Client? httpClient,
}) async {
  final json = await _post(
    config,
    '/v2/accounts/mfaEnrollment:start',
    {'idToken': idToken, 'totpEnrollmentInfo': <String, Object?>{}},
    httpClient: httpClient,
  );
  final info = json['totpSessionInfo'];
  if (info is! Map) throw FirebaseAuthException(mfaFailureMessage(json));
  final session = info['sessionInfo'];
  final secret = info['sharedSecretKey'];
  if (session is! String || secret is! String) {
    throw FirebaseAuthException('Could not start authenticator setup.');
  }
  final label = Uri.encodeComponent(accountLabel);
  final issuer = Uri.encodeComponent('FamFace');
  return TotpEnrollment(
    sessionInfo: session,
    sharedSecretKey: secret,
    otpauthUrl:
        'otpauth://totp/$issuer:$label?secret=$secret&issuer=$issuer&algorithm=SHA1&digits=6&period=30',
  );
}

Future<FirebaseSession> finishTotpEnrollment({
  required FirebasePublicConfig config,
  required String idToken,
  required String sessionInfo,
  required String code,
  http.Client? httpClient,
}) async {
  final json = await _post(
    config,
    '/v2/accounts/mfaEnrollment:finalize',
    {
      'idToken': idToken,
      'displayName': 'Authenticator app',
      'totpVerificationInfo': {
        'sessionInfo': sessionInfo,
        'verificationCode': code.trim(),
      },
    },
    httpClient: httpClient,
  );
  return _session(json);
}

Future<String> startSmsEnrollment({
  required FirebasePublicConfig config,
  required String idToken,
  required String phoneNumber,
  required String recaptchaToken,
  required bool enterprise,
  http.Client? httpClient,
}) async {
  final json = await _post(
    config,
    '/v2/accounts/mfaEnrollment:start',
    {
      'idToken': idToken,
      'phoneEnrollmentInfo': {
        'phoneNumber': phoneNumber,
        ...smsDispatchFields(recaptchaToken, enterprise: enterprise),
      },
    },
    httpClient: httpClient,
  );
  final info = json['phoneSessionInfo'];
  final session = info is Map ? info['sessionInfo'] : null;
  if (session is! String || session.isEmpty) {
    throw FirebaseAuthException(mfaFailureMessage(json));
  }
  return session;
}

Future<FirebaseSession> finishSmsEnrollment({
  required FirebasePublicConfig config,
  required String idToken,
  required String sessionInfo,
  required String code,
  http.Client? httpClient,
}) async {
  final json = await _post(
    config,
    '/v2/accounts/mfaEnrollment:finalize',
    {
      'idToken': idToken,
      'displayName': 'Phone',
      'phoneVerificationInfo': {
        'sessionInfo': sessionInfo,
        'code': code.trim(),
      },
    },
    httpClient: httpClient,
  );
  return _session(json);
}

Future<void> withdrawFactor({
  required FirebasePublicConfig config,
  required String idToken,
  required String enrollmentId,
  http.Client? httpClient,
}) async {
  await _post(
    config,
    '/v2/accounts/mfaEnrollment:withdraw',
    {'idToken': idToken, 'mfaEnrollmentId': enrollmentId},
    httpClient: httpClient,
  );
}

Future<List<MfaFactor>> listFactors({
  required FirebasePublicConfig config,
  required String idToken,
  http.Client? httpClient,
}) async {
  final json = await _post(
    config,
    '/v1/accounts:lookup',
    {'idToken': idToken},
    httpClient: httpClient,
  );
  final users = json['users'];
  if (users is! List || users.isEmpty || users.first is! Map) return const [];
  final info = (users.first as Map)['mfaInfo'];
  final challenge = _factorsFrom(info);
  return challenge;
}

bool idTokenEmailVerified(String idToken) {
  final parts = idToken.split('.');
  if (parts.length < 2) return false;
  try {
    final decoded = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    return decoded is Map && decoded['email_verified'] == true;
  } on FormatException {
    return false;
  }
}

List<MfaFactor> _factorsFrom(Object? info) {
  if (info is! List) return const [];
  final factors = <MfaFactor>[];
  for (final raw in info) {
    if (raw is! Map) continue;
    final id = raw['mfaEnrollmentId'];
    if (id is! String || id.isEmpty) continue;
    final phone = raw['phoneInfo'];
    if (phone is String && phone.isNotEmpty) {
      factors.add(MfaFactor(enrollmentId: id, kind: 'phone', label: phone));
      continue;
    }
    if (raw['totpInfo'] != null) {
      final name = raw['displayName'];
      factors.add(
        MfaFactor(
          enrollmentId: id,
          kind: 'totp',
          label: name is String && name.isNotEmpty
              ? name
              : 'Authenticator app',
        ),
      );
    }
  }
  return factors;
}

Future<Map<String, dynamic>> _post(
  FirebasePublicConfig config,
  String path,
  Map<String, Object?> body, {
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final res = await client.post(
      Uri.parse(
        '$_toolkit$path?key=${Uri.encodeQueryComponent(config.apiKey)}',
      ),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    final decoded = jsonDecode(res.body);
    final json = decoded is Map<String, dynamic>
        ? decoded
        : decoded is Map
        ? decoded.map((k, v) => MapEntry('$k', v))
        : <String, dynamic>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FirebaseAuthException(mfaFailureMessage(json));
    }
    return json;
  } finally {
    if (close) client.close();
  }
}

FirebaseSession _session(Map<String, dynamic> json) {
  final idToken = json['idToken'];
  final refreshToken = json['refreshToken'];
  if (idToken is! String || refreshToken is! String) {
    throw FirebaseAuthException(mfaFailureMessage(json));
  }
  final seconds = int.tryParse(json['expiresIn']?.toString() ?? '') ?? 3600;
  final localId = json['localId'];
  return FirebaseSession(
    idToken: idToken,
    refreshToken: refreshToken,
    expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
    localId: localId is String ? localId : '',
    email: json['email'] is String ? json['email'] as String : null,
  );
}

String mfaFailureMessage(Map<String, dynamic> json) {
  final error = json['error'];
  if (error is Map && error['message'] is String) {
    final code = error['message'] as String;
    if (code.contains('UNVERIFIED_EMAIL')) {
      return 'Verify your email before adding a second factor.';
    }
    if (code.contains('REQUIRES_RECENT_LOGIN')) {
      return 'Sign in again, then add the second factor.';
    }
    if (code.contains('INVALID_CODE') || code.contains('INVALID_OTP')) {
      return 'That code is wrong.';
    }
    if (code.contains('INVALID_APP_CREDENTIAL')) {
      return 'The text message check was rejected. Try again.';
    }
    if (code.contains('INVALID_PHONE_NUMBER')) {
      return 'That phone number is not valid.';
    }
    if (code.contains('OPERATION_NOT_ALLOWED')) {
      return 'Texts to that number are not allowed.';
    }
    if (code.contains('TOO_MANY_ATTEMPTS') || code.contains('QUOTA_EXCEEDED')) {
      return 'Too many texts. Try again later.';
    }
    return code;
  }
  return 'That step failed.';
}
