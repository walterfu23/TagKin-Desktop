import 'dart:convert';

import 'package:http/http.dart' as http;

/// Public sign-in config from `GET /auth/bootstrap`. No server secrets.
class AuthBootstrap {
  const AuthBootstrap({
    required this.providerId,
    this.clerkPublishableKey,
    this.firebase,
  });

  final String providerId;
  final String? clerkPublishableKey;
  final FirebasePublicConfig? firebase;

  bool get isFirebase => providerId == 'firebase';
  bool get isClerk => providerId == 'clerk';

  static AuthBootstrap? tryParse(Object? json) {
    if (json is! Map) return null;
    final providerId = json['providerId'];
    if (providerId is! String || providerId.isEmpty) return null;
    String? clerkKey;
    final clerk = json['clerk'];
    if (clerk is Map && clerk['publishableKey'] is String) {
      final key = (clerk['publishableKey'] as String).trim();
      if (key.isNotEmpty) clerkKey = key;
    }
    FirebasePublicConfig? firebase;
    final rawFirebase = json['firebase'];
    if (rawFirebase is Map) {
      firebase = FirebasePublicConfig.tryParse(rawFirebase);
    }
    return AuthBootstrap(
      providerId: providerId,
      clerkPublishableKey: clerkKey,
      firebase: firebase,
    );
  }
}

class FirebasePublicConfig {
  const FirebasePublicConfig({
    required this.apiKey,
    required this.authDomain,
    required this.projectId,
    this.googleClientId,
  });

  final String apiKey;
  final String authDomain;
  final String projectId;
  final String? googleClientId;

  static FirebasePublicConfig? tryParse(Map raw) {
    final apiKey = raw['apiKey'];
    final authDomain = raw['authDomain'];
    final projectId = raw['projectId'];
    if (apiKey is! String ||
        authDomain is! String ||
        projectId is! String ||
        apiKey.trim().isEmpty ||
        authDomain.trim().isEmpty ||
        projectId.trim().isEmpty) {
      return null;
    }
    final google = raw['googleClientId'];
    return FirebasePublicConfig(
      apiKey: apiKey.trim(),
      authDomain: authDomain.trim(),
      projectId: projectId.trim(),
      googleClientId: google is String && google.trim().isNotEmpty
          ? google.trim()
          : null,
    );
  }
}

/// Fetches the active provider. Returns null when the API is unreachable.
Future<AuthBootstrap?> fetchAuthBootstrap(
  String apiUrl, {
  http.Client? httpClient,
  Duration timeout = const Duration(seconds: 2),
}) async {
  final client = httpClient ?? http.Client();
  final close = httpClient == null;
  try {
    final res = await client
        .get(Uri.parse('$apiUrl/auth/bootstrap'))
        .timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) return null;
    return AuthBootstrap.tryParse(jsonDecode(res.body));
  } catch (_) {
    return null;
  } finally {
    if (close) client.close();
  }
}
