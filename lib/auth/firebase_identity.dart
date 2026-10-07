import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/auth/auth_bootstrap.dart';

class FirebaseAuthException implements Exception {
  FirebaseAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Password sign-in reported that Firebase has no user for that email.
class FirebaseAccountMissing extends FirebaseAuthException {
  FirebaseAccountMissing()
    : super('No account for that email. Create one below.');
}

/// The refresh token can never succeed again (deleted or disabled user,
/// or a refresh token Firebase has rejected).
class FirebaseSessionRevoked extends FirebaseAuthException {
  FirebaseSessionRevoked([super.message = 'That account was removed.']);
}

const _revokedRefreshCodes = <String>{
  'USER_NOT_FOUND',
  'USER_DISABLED',
  'TOKEN_EXPIRED',
  'INVALID_REFRESH_TOKEN',
  'MISSING_REFRESH_TOKEN',
};

class FirebaseSession {
  const FirebaseSession({
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.localId,
    this.email,
    this.isNewUser = false,
  });

  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String localId;
  final String? email;

  /// True only for the sign-in response that created the Firebase user.
  /// Not stored: a relaunch uses the gate marker instead.
  final bool isNewUser;

  Map<String, Object?> toJson() => {
    'idToken': idToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.toIso8601String(),
    'localId': localId,
    'email': email,
  };

  static FirebaseSession? tryParse(Object? json) {
    if (json is! Map) return null;
    final idToken = json['idToken'];
    final refreshToken = json['refreshToken'];
    final localId = json['localId'];
    final expiresAt = json['expiresAt'];
    if (idToken is! String ||
        refreshToken is! String ||
        localId is! String ||
        expiresAt is! String) {
      return null;
    }
    final expiry = DateTime.tryParse(expiresAt);
    if (expiry == null) return null;
    final email = json['email'];
    return FirebaseSession(
      idToken: idToken,
      refreshToken: refreshToken,
      expiresAt: expiry,
      localId: localId,
      email: email is String && email.isNotEmpty ? email : null,
    );
  }
}

class PkcePair {
  const PkcePair({required this.verifier, required this.challenge});
  final String verifier;
  final String challenge;
}

PkcePair createPkcePair({Random? random}) {
  final rng = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
  final verifier = base64Url.encode(bytes).replaceAll('=', '');
  final digest = sha256.convert(utf8.encode(verifier)).bytes;
  final challenge = base64Url.encode(digest).replaceAll('=', '');
  return PkcePair(verifier: verifier, challenge: challenge);
}

/// Google authorize URL for the loopback ("Desktop app" client) flow.
Uri googleAuthorizeUri({
  required String clientId,
  required String redirectUri,
  required String codeChallenge,
  required String state,
}) {
  return Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': 'openid email profile',
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
    'state': state,
    'prompt': 'select_account',
  });
}

class MfaFactor {
  const MfaFactor({
    required this.enrollmentId,
    required this.kind,
    required this.label,
  });

  final String enrollmentId;

  /// `phone` or `totp`.
  final String kind;
  final String label;
}

class MfaChallenge {
  const MfaChallenge({required this.pendingCredential, required this.factors});

  final String pendingCredential;
  final List<MfaFactor> factors;
}

/// Identity Toolkit accepted the first factor and still needs SMS or TOTP.
class MfaRequired implements Exception {
  MfaRequired(this.challenge);
  final MfaChallenge challenge;
  @override
  String toString() => 'A second factor is required.';
}

class EmailCodeStart {
  const EmailCodeStart({required this.emailMasked});

  final String emailMasked;
}

/// Asks the API to email a sign-in code for [email]. No bearer. The response
/// never includes the code, and it looks the same when the address is unknown.
Future<EmailCodeStart> requestEmailSignInCode({
  required String apiUrl,
  required String email,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final res = await client.post(
      Uri.parse('$apiUrl/auth/email-code'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email.trim()}),
    );
    final json = _jsonMap(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FirebaseAuthException(_apiMessage(json, res.statusCode));
    }
    final masked = json['emailMasked'];
    if (masked is! String || masked.isEmpty) {
      throw FirebaseAuthException(
        'Sign-in did not say where the code was sent.',
      );
    }
    return EmailCodeStart(emailMasked: masked);
  } finally {
    if (close) client.close();
  }
}

/// Returns the one-time Firebase email-link code. The caller exchanges it
/// and does not show it.
Future<String> verifyEmailSignInCode({
  required String apiUrl,
  required String email,
  required String code,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final res = await client.post(
      Uri.parse('$apiUrl/auth/email-code/verify'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'code': code.trim()}),
    );
    final json = _jsonMap(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw FirebaseAuthException(_apiMessage(json, res.statusCode));
    }
    final oob = json['oobCode'];
    if (oob is! String || oob.isEmpty) {
      throw FirebaseAuthException('Sign-in did not return a session.');
    }
    return oob;
  } finally {
    if (close) client.close();
  }
}

Future<FirebaseSession> signInWithPassword({
  required FirebasePublicConfig config,
  required String email,
  required String password,
  required bool signUp,
  http.Client? httpClient,
}) {
  return _passwordGrant(
    config: config,
    email: email,
    password: password,
    method: signUp ? 'signUp' : 'signInWithPassword',
    forceNewUser: signUp,
    httpClient: httpClient,
  );
}

Future<FirebaseSession> refreshFirebaseSession({
  required FirebasePublicConfig config,
  required String refreshToken,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final http.Response res;
    try {
      res = await client.post(
        Uri.parse(
          'https://securetoken.googleapis.com/v1/token?key=${Uri.encodeQueryComponent(config.apiKey)}',
        ),
        headers: {'content-type': 'application/x-www-form-urlencoded'},
        body: {'grant_type': 'refresh_token', 'refresh_token': refreshToken},
      );
    } on FirebaseAuthException {
      rethrow;
    } on Object {
      throw FirebaseAuthException('Sign-in failed.');
    }
    final json = _jsonMap(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      if (res.statusCode >= 400 &&
          res.statusCode < 500 &&
          _isSessionRevoked(json)) {
        throw FirebaseSessionRevoked(_firebaseMessage(json));
      }
      throw FirebaseAuthException(_firebaseMessage(json));
    }
    final idToken = json['id_token'];
    final nextRefresh = json['refresh_token'];
    final expiresIn = json['expires_in'];
    final userId = json['user_id'];
    if (idToken is! String || nextRefresh is! String || userId is! String) {
      throw FirebaseAuthException('Sign-in did not return a session.');
    }
    final seconds = int.tryParse(expiresIn?.toString() ?? '') ?? 3600;
    final email = _emailFromIdToken(idToken) ?? json['email'];
    return FirebaseSession(
      idToken: idToken,
      refreshToken: nextRefresh,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
      localId: userId,
      email: email is String && email.isNotEmpty ? email : null,
    );
  } finally {
    if (close) client.close();
  }
}

/// Completes Google sign-in: the TagKin API exchanges the one-time [code] for a
/// Google ID token (the Desktop-app client secret stays server-side, R8), then
/// Firebase Identity Toolkit turns that into a Firebase session.
Future<FirebaseSession> signInWithGoogleCode({
  required FirebasePublicConfig config,
  required String apiUrl,
  required String code,
  required String codeVerifier,
  required String redirectUri,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final tokenRes = await client.post(
      Uri.parse('$apiUrl/auth/google/token'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'code': code,
        'codeVerifier': codeVerifier,
        'redirectUri': redirectUri,
      }),
    );
    final tokenJson = _jsonMap(tokenRes);
    if (tokenRes.statusCode < 200 || tokenRes.statusCode >= 300) {
      final message = tokenJson['message'];
      throw FirebaseAuthException(
        message is String && message.isNotEmpty
            ? message
            : 'Google sign-in failed (${tokenRes.statusCode}).',
      );
    }
    final googleIdToken = tokenJson['idToken'];
    if (googleIdToken is! String || googleIdToken.isEmpty) {
      throw FirebaseAuthException('Google did not return a sign-in token.');
    }
    final res = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${Uri.encodeQueryComponent(config.apiKey)}',
      ),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'postBody':
            'id_token=${Uri.encodeQueryComponent(googleIdToken)}&providerId=google.com',
        'requestUri': 'http://localhost',
        'returnSecureToken': true,
      }),
    );
    return _sessionFromIdentity(res);
  } finally {
    if (close) client.close();
  }
}

/// Exchanges the one-time code from [verifyEmailSignInCode].
Future<FirebaseSession> signInWithEmailLink({
  required FirebasePublicConfig config,
  required String email,
  required String oobCode,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final res = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:signInWithEmailLink?key=${Uri.encodeQueryComponent(config.apiKey)}',
      ),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'email': email.trim(), 'oobCode': oobCode}),
    );
    return _sessionFromIdentity(res);
  } finally {
    if (close) client.close();
  }
}

Future<FirebaseSession> _passwordGrant({
  required FirebasePublicConfig config,
  required String email,
  required String password,
  required String method,
  bool forceNewUser = false,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final res = await client.post(
      Uri.parse(
        'https://identitytoolkit.googleapis.com/v1/accounts:$method?key=${Uri.encodeQueryComponent(config.apiKey)}',
      ),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email.trim(),
        'password': password,
        'returnSecureToken': true,
      }),
    );
    if (method == 'signInWithPassword' &&
        _firebaseErrorCode(_jsonMap(res)) == 'EMAIL_NOT_FOUND') {
      throw FirebaseAccountMissing();
    }
    return _sessionFromIdentity(res, forceNewUser: forceNewUser);
  } finally {
    if (close) client.close();
  }
}

FirebaseSession _sessionFromIdentity(
  http.Response res, {
  bool forceNewUser = false,
}) {
  final json = _jsonMap(res);
  final challenge = _mfaChallenge(json);
  if (challenge != null) throw MfaRequired(challenge);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw FirebaseAuthException(_firebaseMessage(json));
  }
  final idToken = json['idToken'];
  final refreshToken = json['refreshToken'];
  final localId = json['localId'];
  if (idToken is! String || refreshToken is! String || localId is! String) {
    throw FirebaseAuthException('Sign-in did not return a session.');
  }
  final seconds = int.tryParse(json['expiresIn']?.toString() ?? '') ?? 3600;
  final email = json['email'] ?? _emailFromIdToken(idToken);
  return FirebaseSession(
    idToken: idToken,
    refreshToken: refreshToken,
    expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
    localId: localId,
    email: email is String && email.isNotEmpty ? email : null,
    isNewUser: forceNewUser || json['isNewUser'] == true,
  );
}

MfaChallenge? _mfaChallenge(Map<String, dynamic> json) {
  var pending = json['mfaPendingCredential'];
  var info = json['mfaInfo'];
  final error = json['error'];
  if (error is Map && error['message'] is String) {
    final message = error['message'] as String;
    final colon = message.indexOf('{');
    if (colon >= 0) {
      try {
        final embedded = jsonDecode(message.substring(colon));
        if (embedded is Map) {
          pending ??= embedded['mfaPendingCredential'];
          info ??= embedded['mfaInfo'];
        }
      } on FormatException {
        // The error text is not an embedded MFA payload.
      }
    }
  }
  if (pending is! String || pending.isEmpty || info is! List) return null;
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
          label: name is String && name.isNotEmpty ? name : 'Authenticator app',
        ),
      );
    }
  }
  if (factors.isEmpty) return null;
  return MfaChallenge(pendingCredential: pending, factors: factors);
}

String? _emailFromIdToken(String idToken) {
  final payload = _jwtPayload(idToken);
  final email = payload?['email'];
  return email is String && email.isNotEmpty ? email : null;
}

Map<String, dynamic>? _jwtPayload(String jwt) {
  final parts = jwt.split('.');
  if (parts.length < 2) return null;
  try {
    final normalized = base64Url.normalize(parts[1]);
    final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
  } on FormatException {
    return null;
  }
  return null;
}

Map<String, dynamic> _jsonMap(http.Response res) {
  try {
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
  } on FormatException {
    return {};
  }
  return {};
}

String _apiMessage(Map<String, dynamic> json, int status) {
  final message = json['message'];
  if (message is String && message.isNotEmpty) return message;
  return 'Sign-in code failed ($status).';
}

String? _firebaseErrorCode(Map<String, dynamic> json) {
  final error = json['error'];
  if (error is! Map || error['message'] is! String) return null;
  final message = error['message'] as String;
  final colon = message.indexOf(':');
  return colon >= 0 ? message.substring(0, colon) : message;
}

bool _isSessionRevoked(Map<String, dynamic> json) {
  final blobs = <String>[];
  final code = _firebaseErrorCode(json);
  if (code != null) blobs.add(code);
  final error = json['error'];
  if (error is String && error.isNotEmpty) blobs.add(error);
  final description = json['error_description'];
  if (description is String && description.isNotEmpty) blobs.add(description);
  for (final blob in blobs) {
    for (final revoked in _revokedRefreshCodes) {
      if (blob == revoked ||
          blob.startsWith('$revoked ') ||
          blob.startsWith('$revoked:')) {
        return true;
      }
    }
  }
  return false;
}

String _firebaseMessage(Map<String, dynamic> json) {
  final error = json['error'];
  if (error is Map && error['message'] is String) {
    return _friendly((error['message'] as String));
  }
  if (json['error_description'] is String) {
    return json['error_description'] as String;
  }
  return 'Sign-in failed.';
}

String _friendly(String code) {
  switch (code) {
    case 'EMAIL_NOT_FOUND':
    case 'INVALID_PASSWORD':
    case 'INVALID_LOGIN_CREDENTIALS':
      return 'Email or password is incorrect.';
    case 'EMAIL_EXISTS':
      return 'An account with that email already exists. Sign in instead.';
    case 'WEAK_PASSWORD':
      return 'Password must be at least 6 characters.';
    default:
      return 'Sign-in failed ($code).';
  }
}
