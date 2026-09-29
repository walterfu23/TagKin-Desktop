import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/prepass/face_embedder.dart';
import 'package:tagkin_desktop/prepass/prepass_payload_builder.dart';

Future<File> _writeSolidJpeg(Directory dir, String name) async {
  final image = img.Image(width: 32, height: 32);
  img.fill(image, color: img.ColorRgb8(80, 80, 80));
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(img.encodeJpg(image));
  return file;
}

void main() {
  group('buildPrePassPayload', () {
    test('photo payload has contentHash, pHash, 512-d appearance; no bytes',
        () async {
      final dir = await Directory.systemTemp.createTemp('tagkin_prepass_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = await _writeSolidJpeg(dir, 'a.jpg');

      final built = await buildPrePassPayload(
        path: file.path,
        type: ItemType.photo,
      );
      final payload = built.payload;
      final json = jsonEncode(payload.toJson());

      expect(payload.contentHash, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(payload.perceptualHash, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(payload.appearances, isNotNull);
      expect(payload.appearances!.single.embedding, hasLength(kFaceEmbeddingDim));
      expect(json.toLowerCase(), isNot(contains('base64')));
      expect(json.toLowerCase(), isNot(contains('imagedata')));
      expect(json.contains('"bytes"'), isFalse);
      expect(json.contains('ownerUserId'), isFalse);
      expect(json.contains('accountId'), isFalse);
    });

    test('skipFaces omits appearances', () async {
      final dir = await Directory.systemTemp.createTemp('tagkin_prepass_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = await _writeSolidJpeg(dir, 'b.jpg');

      final built = await buildPrePassPayload(
        path: file.path,
        type: ItemType.photo,
        skipFaces: true,
      );
      expect(built.payload.appearances, isEmpty);
    });

    test('injectable FaceEmbedder is used', () async {
      final dir = await Directory.systemTemp.createTemp('tagkin_prepass_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = await _writeSolidJpeg(dir, 'c.jpg');

      final built = await buildPrePassPayload(
        path: file.path,
        type: ItemType.photo,
        faceEmbedder: _FixedEmbedder(),
      );
      expect(built.payload.appearances!.single.embeddingModelId, 'fixed-v1');
      expect(built.payload.appearances!.single.embedding, hasLength(512));
    });
  });
}

class _FixedEmbedder implements FaceEmbedder {
  @override
  Future<List<FaceAppearance>> embed(Uint8List bytes) async {
    return [
      FaceAppearance(
        embedding: List<double>.filled(512, 0.0)..[0] = 1.0,
        embeddingModelId: 'fixed-v1',
      ),
    ];
  }
}
