import 'dart:convert';

import 'package:http/http.dart' as http;

/// Result of a direct client → model-host PUT (D5).
///
/// Never talks to tagkin-api; never carries a provider key (R8).
class ModelHostUploadResult {
  const ModelHostUploadResult({
    required this.analysisRef,
    required this.rawBody,
  });

  /// Opaque file URI / analysisRef from the model host, when parseable.
  final String? analysisRef;

  /// Raw response text for debugging when JSON parse fails.
  final String rawBody;
}

/// PUT bytes to a server-minted model-host upload URL.
///
/// Uses a bare [http.Client] — never [ApiClient], never an `Authorization`
/// header (R8). Bytes go client → model host only (R1/R5).
///
/// Mirrors `tagkin-web`'s `putBytesToUploadUrl` (Gemini Files API resumable
/// finalize headers).
Future<ModelHostUploadResult> putBytesToUploadUrl({
  required String uploadUrl,
  required List<int> bytes,
  required String mimeType,
  http.Client? httpClient,
}) async {
  final client = httpClient ?? http.Client();
  final ownsClient = httpClient == null;
  try {
    final uri = Uri.parse(uploadUrl);
    final response = await client.put(
      uri,
      headers: {
        'Content-Type': mimeType,
        'X-Goog-Upload-Command': 'upload, finalize',
        'X-Goog-Upload-Offset': '0',
      },
      body: bytes,
    );
    final rawBody = response.body;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ModelHostUploadException(
        statusCode: response.statusCode,
        message: rawBody.isEmpty
            ? 'Direct upload failed'
            : rawBody.length > 200
                ? rawBody.substring(0, 200)
                : rawBody,
      );
    }
    return ModelHostUploadResult(
      analysisRef: _parseAnalysisRef(rawBody),
      rawBody: rawBody,
    );
  } finally {
    if (ownsClient) client.close();
  }
}

String? _parseAnalysisRef(String rawBody) {
  if (rawBody.isEmpty) return null;
  try {
    final json = jsonDecode(rawBody);
    if (json is! Map) return null;
    final file = json['file'];
    if (file is Map) {
      final uri = file['uri'];
      if (uri is String && uri.isNotEmpty) return uri;
      final name = file['name'];
      if (name is String && name.isNotEmpty) {
        final stripped = name.replaceFirst(RegExp(r'^files/'), '');
        return 'files/$stripped';
      }
    }
    final uri = json['uri'];
    if (uri is String && uri.isNotEmpty) return uri;
  } on FormatException {
    return null;
  }
  return null;
}

/// Thrown when the model-host PUT returns a non-2xx status.
class ModelHostUploadException implements Exception {
  ModelHostUploadException({
    required this.statusCode,
    required this.message,
  });

  final int statusCode;
  final String message;

  @override
  String toString() => 'ModelHostUploadException($statusCode): $message';
}
