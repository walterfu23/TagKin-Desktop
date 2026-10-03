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

class FirebaseSession {
  const FirebaseSession({
    required this.idToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.localId,
    this.email,
  });

  final String idToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String localId;
  final String? email;

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

Uri googleAuthorizeUri({
  required String clientId,
  required String redirectUri,
  required String codeChallenge,
}) {
  return Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': 'openid email profile',
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
    'prompt': 'select_account',
  });
}

const String kFirebaseOauthRedirect = 'tagkindesktop://oauth/callback';

String? oauthCodeFromRedirect(Uri uri) {
  if (uri.scheme != 'tagkindesktop') return null;
  final code = uri.queryParameters['code'];
  if (code == null || code.isEmpty) return null;
  return code;
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
    final res = await client.post(
      Uri.parse(
        'https://securetoken.googleapis.com/v1/token?key=${Uri.encodeQueryComponent(config.apiKey)}',
      ),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
      },
    );
    final json = _jsonMap(res);
    if (res.statusCode < 200 || res.statusCode >= 300) {
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
    return FirebaseSession(
      idToken: idToken,
      refreshToken: nextRefresh,
      expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
      localId: userId,
    );
  } finally {
    if (close) client.close();
  }
}

Future<FirebaseSession> signInWithGoogleCode({
  required FirebasePublicConfig config,
  required String code,
  required String codeVerifier,
  required String redirectUri,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final tokenRes = await client.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: {
        'code': code,
        'client_id': config.googleClientId ?? '',
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': codeVerifier,
      },
    );
    final tokenJson = _jsonMap(tokenRes);
    if (tokenRes.statusCode < 200 || tokenRes.statusCode >= 300) {
      throw FirebaseAuthException(_firebaseMessage(tokenJson));
    }
    final googleIdToken = tokenJson['id_token'];
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

Future<FirebaseSession> _passwordGrant({
  required FirebasePublicConfig config,
  required String email,
  required String password,
  required String method,
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
    return _sessionFromIdentity(res);
  } finally {
    if (close) client.close();
  }
}

FirebaseSession _sessionFromIdentity(http.Response res) {
  final json = _jsonMap(res);
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
  final email = json['email'];
  return FirebaseSession(
    idToken: idToken,
    refreshToken: refreshToken,
    expiresAt: DateTime.now().toUtc().add(Duration(seconds: seconds)),
    localId: localId,
    email: email is String ? email : null,
  );
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
