import 'dart:io';
import 'dart:typed_data';

import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/content_hash.dart';
import 'package:tagkin_desktop/ingest/perceptual_hash.dart';
import 'package:tagkin_desktop/prepass/exif_extract.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/frame_sampler.dart';
import 'package:tagkin_desktop/prepass/scene_detect.dart';

/// Result of a local classic pre-pass: contract payload + optional frame
/// samples for D5 (bytes stay local; never posted to tagkin-api).
class PrePassBuildResult {
  const PrePassBuildResult({
    required this.payload,
    this.frameSamples = const [],
  });

  final PrePassResult payload;
  final List<FrameSample> frameSamples;
}

/// Run the classic Free/Classic pre-pass and return a contract-shaped payload
/// (no media bytes — R1/R5/R9).
Future<PrePassBuildResult> buildPrePassPayload({
  required String path,
  required ItemType type,
  FaceEmbedder? faceEmbedder,
  bool skipFaces = false,
  int maxFrames = kDefaultMaxFramesPerItem,
}) async {
  final contentHash = await computeContentHash(path);
  final bytes = await File(path).readAsBytes();

  String? capturedAt;
  PrePassWhere? where;
  String? perceptualHash;
  int? durationMs;
  List<PrePassKeyPeriodInput>? keyPeriods;
  final appearances = <PrePassAppearanceInput>[];
  var frameSamples = <FrameSample>[];

  if (type == ItemType.photo) {
    final exif = await extractExif(bytes);
    capturedAt = exif.capturedAt;
    where = exif.where;
    perceptualHash = computePerceptualHash(bytes);

    if (!skipFaces) {
      final embedder = faceEmbedder ?? getFaceEmbedder();
      final faces = await embedder.embed(bytes);
      for (final f in faces) {
        appearances.add(
          PrePassAppearanceInput(
            embedding: f.embedding,
            embeddingModelId: f.embeddingModelId,
          ),
        );
      }
    }
  } else if (type == ItemType.video) {
    // Container-level EXIF/XMP may still carry creation time / GPS.
    final exif = await extractExif(bytes);
    capturedAt = exif.capturedAt;
    where = exif.where;

    if (hasFfmpeg()) {
      try {
        final scene = await detectSceneKeyPeriods(path);
        durationMs = scene.durationMs;
        keyPeriods = scene.keyPeriods;
        frameSamples = await sampleFrames(
          videoPath: path,
          keyPeriods: scene.keyPeriods,
          maxFrames: maxFrames,
        );

        if (!skipFaces && frameSamples.isNotEmpty) {
          final embedder = faceEmbedder ?? getFaceEmbedder();
          for (final sample in frameSamples) {
            final frameBytes = await File(sample.path).readAsBytes();
            final faces = await embedder.embed(
              Uint8List.fromList(frameBytes),
            );
            for (final f in faces) {
              appearances.add(
                PrePassAppearanceInput(
                  keyPeriodIndex: sample.keyPeriodIndex,
                  embedding: f.embedding,
                  embeddingModelId: f.embeddingModelId,
                ),
              );
            }
          }
        }
      } catch (_) {
        // ffmpeg/ffprobe optional — degrade to no key periods / frames.
        durationMs = null;
        keyPeriods = const [];
        frameSamples = const [];
      }
    }
  }

  return PrePassBuildResult(
    payload: PrePassResult(
      contentHash: contentHash,
      perceptualHash: perceptualHash,
      capturedAt: capturedAt,
      where: where,
      durationMs: durationMs,
      keyPeriods: keyPeriods,
      appearances: appearances,
    ),
    frameSamples: frameSamples,
  );
}
