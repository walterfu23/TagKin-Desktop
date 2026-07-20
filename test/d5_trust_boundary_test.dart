import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/model_host_uploader.dart';
import 'package:tagkin_desktop/ingest/upload_controller.dart';
import 'package:tagkin_desktop/prepass/prepass_controller.dart';

import 'fake_items_repository.dart';

/// D5 §5 mandatory assertions: no owner/scope, no media bytes to api,
/// no long-lived secrets / server-only logic in the upload path.
void main() {
  test('lib/ingest upload files never embed provider keys (R8)', () {
    final files = [
      'lib/ingest/upload_controller.dart',
      'lib/ingest/model_host_uploader.dart',
      'lib/ingest/upload_mime.dart',
    ];
    final offenders = <String>[];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      if (source.contains('CLERK_SECRET_KEY') ||
          source.contains('sk_test_') ||
          source.contains('sk_live_') ||
          source.contains('GEMINI_API_KEY') ||
          RegExp(r'AIza[0-9A-Za-z\-_]{20,}').hasMatch(source)) {
        offenders.add(path);
      }
    }
    expect(offenders, isEmpty, reason: 'secret patterns in: $offenders');
  });

  test('upload path never implements grant minting / cost / similarity (R8/§4)',
      () {
    final files = [
      'lib/ingest/upload_controller.dart',
      'lib/ingest/model_host_uploader.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      // Consumes upload-grant API; must not mint grants itself.
      expect(source.contains('x-goog-api-key'), isFalse);
      expect(source.contains('reserve('), isFalse);
      expect(source.contains('cosineSimilarity'), isFalse);
      expect(source.contains('estimateCost'), isFalse);
    }
  });

  test('grant + analysis-ref bodies never carry owner or bytes (R10/R1)',
      () async {
    final dir = await Directory.systemTemp.createTemp('d5_trust_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final image = img.Image(width: 8, height: 8);
    img.fill(image, color: img.ColorRgb8(1, 2, 3));
    final file = File('${dir.path}/shot.jpg');
    await file.writeAsBytes(img.encodeJpg(image));

    final item = fixtureItem(id: 'item_trust_d5', type: ItemType.photo);
    final repo = FakeItemsRepository(items: [item]);
    final controller = UploadController(
      itemsRepository: repo,
      putBytes: ({
        required uploadUrl,
        required bytes,
        required mimeType,
        httpClient,
      }) async {
        // Bytes go to model host only — assert URL is not an /items path.
        expect(uploadUrl.contains('/items'), isFalse);
        expect(uploadUrl.contains('/upload-grant'), isFalse);
        return const ModelHostUploadResult(
          analysisRef: 'files/trust',
          rawBody: '{}',
        );
      },
    );

    await controller.run(
      [
        PrePassOutcome(
          itemId: item.id,
          path: file.path,
          response: PrePassResultResponse(
            item: item,
            keyPeriodIds: const [],
            appearanceIds: const [],
            tagIds: const [],
          ),
        ),
      ],
      const {},
    );

    expect(controller.outcomes.single.succeeded, isTrue);
    final grantBody = repo.grantsMinted.single.input.toJson();
    expect(grantBody.containsKey('ownerUserId'), isFalse);
    expect(grantBody.containsKey('accountId'), isFalse);
    expect(grantBody.containsKey('bytes'), isFalse);
    expect(grantBody.keys.toSet(), {'mimeType'});

    final refBody = repo.analysisRefRecorded.single.input.toJson();
    expect(refBody.containsKey('ownerUserId'), isFalse);
    expect(refBody.containsKey('bytes'), isFalse);
    expect(refBody.keys.toSet(), {'analysisRef'});
  });
}
