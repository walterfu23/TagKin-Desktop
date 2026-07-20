import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';

void main() {
  group('putBytesToUploadUrl', () {
    test('PUTs bytes to the grant URL with Gemini finalize headers (R8)',
        () async {
      Uri? recordedUri;
      Map<String, String>? recordedHeaders;
      List<int>? recordedBody;

      final mock = MockClient((request) async {
        recordedUri = request.url;
        recordedHeaders = request.headers;
        recordedBody = request.bodyBytes;
        return http.Response(
          jsonEncode({
            'file': {'uri': 'https://generativelanguage.googleapis.com/v1beta/files/abc', 'name': 'files/abc'},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final result = await putBytesToUploadUrl(
        uploadUrl: 'https://model-host.example/upload?token=xyz',
        bytes: [1, 2, 3, 4],
        mimeType: 'image/jpeg',
        httpClient: mock,
      );

      expect(recordedUri!.host, 'model-host.example');
      expect(recordedUri!.path, '/upload');
      expect(recordedHeaders!['Content-Type'], 'image/jpeg');
      expect(recordedHeaders!['X-Goog-Upload-Command'], 'upload, finalize');
      expect(recordedHeaders!['X-Goog-Upload-Offset'], '0');
      expect(recordedHeaders!.containsKey('Authorization'), isFalse);
      expect(recordedBody, [1, 2, 3, 4]);
      expect(
        result.analysisRef,
        'https://generativelanguage.googleapis.com/v1beta/files/abc',
      );
    });

    test('never targets a tagkin-api /items path (R1/R5 request-target)',
        () async {
      Uri? recordedUri;
      final mock = MockClient((request) async {
        recordedUri = request.url;
        return http.Response('{"uri":"files/x"}', 200);
      });

      await putBytesToUploadUrl(
        uploadUrl: 'https://stub.tagkin.test/upload',
        bytes: [9],
        mimeType: 'image/jpeg',
        httpClient: mock,
      );

      expect(recordedUri!.host, isNot('localhost'));
      expect(recordedUri!.path.contains('/items'), isFalse);
      expect(recordedUri!.path.contains('/upload-grant'), isFalse);
      expect(recordedUri!.path.contains('/analysis-ref'), isFalse);
    });

    test('parses file.name when uri is absent', () async {
      final mock = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'file': {'name': 'files/named-ref'},
          }),
          200,
        );
      });
      final result = await putBytesToUploadUrl(
        uploadUrl: 'https://host.test/u',
        bytes: [1],
        mimeType: 'image/jpeg',
        httpClient: mock,
      );
      expect(result.analysisRef, 'files/named-ref');
    });

    test('returns null analysisRef on non-JSON stub body', () async {
      final mock = MockClient((request) async {
        return http.Response('ok', 200);
      });
      final result = await putBytesToUploadUrl(
        uploadUrl: 'https://stub.tagkin.test/upload',
        bytes: [1],
        mimeType: 'image/jpeg',
        httpClient: mock,
      );
      expect(result.analysisRef, isNull);
    });

    test('throws ModelHostUploadException on non-2xx', () async {
      final mock = MockClient((request) async {
        return http.Response('expired', 403);
      });
      await expectLater(
        putBytesToUploadUrl(
          uploadUrl: 'https://host.test/u',
          bytes: [1],
          mimeType: 'image/jpeg',
          httpClient: mock,
        ),
        throwsA(
          isA<ModelHostUploadException>()
              .having((e) => e.statusCode, 'status', 403),
        ),
      );
    });
  });
}
