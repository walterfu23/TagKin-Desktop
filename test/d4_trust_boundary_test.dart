import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/batch_ingest_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';

import 'fake_items_repository.dart';

/// D4 §5 mandatory assertions: no owner/scope, no media bytes to api,
/// no long-lived secrets / server-only logic in the pre-pass path.
void main() {
  test('lib/prepass never embeds provider keys or secrets (R8)', () {
    final dir = Directory('lib/prepass');
    expect(dir.existsSync(), isTrue);
    final offenders = <String>[];
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('CLERK_SECRET_KEY') ||
          source.contains('sk_test_') ||
          source.contains('sk_live_') ||
          source.contains('GEMINI_API_KEY') ||
          RegExp(r'AIza[0-9A-Za-z\-_]{20,}').hasMatch(source)) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: 'secret patterns in: $offenders');
  });

  test('pre-pass path never implements grant/cost/similarity (R8/§4)', () {
    final dir = Directory('lib/prepass');
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      expect(source.contains('upload-grant'), isFalse);
      expect(source.contains('reserve('), isFalse);
      expect(source.contains('cosineSimilarity'), isFalse);
    }
  });

  test('controller posts only PrePassResult fields — no owner/bytes (R10/R1)',
      () async {
    final dir = await Directory.systemTemp.createTemp('d4_trust_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final image = img.Image(width: 16, height: 16);
    img.fill(image, color: img.ColorRgb8(10, 20, 30));
    final file = File('${dir.path}/shot.jpg');
    await file.writeAsBytes(img.encodeJpg(image));

    final item = fixtureItem(id: 'item_trust', type: ItemType.photo);
    final repo = FakeItemsRepository(items: [item]);
    final controller = PrePassController(itemsRepository: repo);

    await controller.run([
      IngestOutcome(path: file.path, item: item),
    ]);

    expect(controller.outcomes.single.succeeded, isTrue);
    expect(repo.prePassRecorded, hasLength(1));
    final body = repo.prePassRecorded.single.input.toJson();
    expect(body.containsKey('ownerUserId'), isFalse);
    expect(body.containsKey('bytes'), isFalse);
    expect(body['contentHash'], isA<String>());
    expect(body['appearances'], isA<List<dynamic>>());
  });
}
