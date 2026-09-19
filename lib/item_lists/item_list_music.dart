import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/contract/contract.dart';

/// Client for `POST /music/estimate` and `POST /music/generate`.
///
/// Prompt + duration, plus optional opaque ids of earlier takes (R1). Never
/// sends owner/scope (R10). Credits come from the server — this client does
/// not estimate cents (R9). Desktop never learns which vendor ran (R8).
class MusicRepository {
  MusicRepository(this._client);

  final ApiClient _client;

  static const generateTimeout = Duration(minutes: 3);

  /// `POST /music/estimate`
  Future<EstimateMusicResponse> estimate({required int durationMs}) async {
    final response = await _client.post(
      '/music/estimate',
      body: EstimateMusicRequest(durationMs: durationMs).toJson(),
    );
    return EstimateMusicResponse.fromJson(
      _client.decodeMap(response, '/music/estimate'),
    );
  }

  /// `POST /music/generate` — TagKin-produced audio, not user media.
  Future<GenerateMusicResponse> generate({
    required int durationMs,
    required String prompt,
    List<String>? avoidSoundtrackIds,
  }) async {
    final avoid = avoidSoundtrackIds
        ?.map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    final response = await _client.post(
      '/music/generate',
      body: GenerateMusicRequest(
        durationMs: durationMs,
        prompt: prompt,
        avoidSoundtrackIds: (avoid == null || avoid.isEmpty) ? null : avoid,
      ).toJson(),
      timeout: generateTimeout,
    );
    return GenerateMusicResponse.fromJson(
      _client.decodeMap(response, '/music/generate'),
    );
  }

  /// Decode [GenerateMusicResponse.audioBase64] to a temp file.
  Future<File> writeAudioTemp(GenerateMusicResponse generated) async {
    final bytes = Uint8List.fromList(base64Decode(generated.audioBase64));
    final ext = _extForMime(generated.mimeType);
    final dir = await Directory.systemTemp.createTemp('tagkin-music-');
    final file = File(p.join(dir.path, 'soundtrack$ext'));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

String _extForMime(String mimeType) {
  final mime = mimeType.split(';').first.trim().toLowerCase();
  switch (mime) {
    case 'audio/wav':
    case 'audio/x-wav':
    case 'audio/wave':
      return '.wav';
    case 'audio/mpeg':
    case 'audio/mp3':
      return '.mp3';
    case 'audio/mp4':
    case 'audio/aac':
      return '.m4a';
    default:
      return '.bin';
  }
}
