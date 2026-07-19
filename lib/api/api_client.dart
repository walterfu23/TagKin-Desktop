import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thrown when tagkin-api returns 401 Unauthorized.
///
/// Callers must route to sign-in — [ApiClient] never silently retries.
class UnauthorizedException implements Exception {
  UnauthorizedException({this.message = 'Unauthorized'});

  final String message;

  @override
  String toString() => 'UnauthorizedException: $message';
}

/// Thrown for non-401 HTTP failures with the contract [Error] shape when present.
class ApiException implements Exception {
  ApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Supplies a bearer JWT for authenticated tagkin-api calls.
typedef TokenProvider = FutureOr<String?> Function();

/// Base HTTP client for tagkin-api.
///
/// Injects `Authorization: Bearer <token>` from [tokenProvider], maps 401 →
/// [UnauthorizedException] (no retry loop), and never invents owner/scope
/// fields (R10). Downstream subsystems should use this for every API call.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokenProvider,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// tagkin-api origin, no trailing slash.
  final String baseUrl;

  /// Returns the current Clerk session JWT, or null when signed out.
  final TokenProvider tokenProvider;

  final http.Client _http;

  /// Outgoing request log for tests (method, path, headers, body).
  final List<ApiRequestRecord> recordedRequests = <ApiRequestRecord>[];

  /// Whether to append to [recordedRequests] (enabled in tests).
  bool recordRequests = false;

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalized').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
    };
    if (jsonBody) {
      headers['Content-Type'] = 'application/json';
    }
    final token = await tokenProvider();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  void _record({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) {
    if (!recordRequests) return;
    recordedRequests.add(
      ApiRequestRecord(
        method: method,
        uri: uri,
        headers: Map<String, String>.from(headers),
        body: body,
      ),
    );
  }

  Future<http.Response> get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query);
    final headers = await _headers();
    _record(method: 'GET', uri: uri, headers: headers);
    final response = await _http.get(uri, headers: headers);
    return _guard(response);
  }

  Future<http.Response> post(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query);
    final encoded = body == null ? null : jsonEncode(body);
    final headers = await _headers(jsonBody: body != null);
    _record(method: 'POST', uri: uri, headers: headers, body: encoded);
    final response = await _http.post(uri, headers: headers, body: encoded);
    return _guard(response);
  }

  Future<http.Response> patch(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query);
    final encoded = body == null ? null : jsonEncode(body);
    final headers = await _headers(jsonBody: body != null);
    _record(method: 'PATCH', uri: uri, headers: headers, body: encoded);
    final response = await _http.patch(uri, headers: headers, body: encoded);
    return _guard(response);
  }

  Future<http.Response> delete(
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final uri = _uri(path, query);
    final encoded = body == null ? null : jsonEncode(body);
    final headers = await _headers(jsonBody: body != null);
    _record(method: 'DELETE', uri: uri, headers: headers, body: encoded);
    final response = await _http.delete(uri, headers: headers, body: encoded);
    return _guard(response);
  }

  http.Response _guard(http.Response response) {
    if (response.statusCode == 401) {
      throw UnauthorizedException(
        message: _messageFromBody(response.body) ?? 'Unauthorized',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final parsed = _tryParseError(response.body);
      throw ApiException(
        statusCode: response.statusCode,
        message: parsed?.message ?? response.reasonPhrase ?? 'Request failed',
        code: parsed?.code,
      );
    }
    return response;
  }

  static String? _messageFromBody(String body) {
    return _tryParseError(body)?.message;
  }

  static ({String? code, String message})? _tryParseError(String body) {
    if (body.isEmpty) return null;
    try {
      final json = jsonDecode(body);
      if (json is Map<String, dynamic>) {
        final message = json['message'];
        if (message is String) {
          final code = json['code'];
          return (code: code is String ? code : null, message: message);
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  void close() => _http.close();
}

/// Snapshot of an outgoing [ApiClient] request (test assertion surface).
class ApiRequestRecord {
  const ApiRequestRecord({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;

  /// True when the JSON body contains a client-supplied owner/scope field.
  bool get bodyContainsOwnerField {
    if (body == null || body!.isEmpty) return false;
    try {
      final decoded = jsonDecode(body!);
      if (decoded is! Map) return false;
      return decoded.containsKey('ownerUserId') ||
          decoded.containsKey('accountId') ||
          decoded.containsKey('ownerId');
    } on FormatException {
      return false;
    }
  }
}
