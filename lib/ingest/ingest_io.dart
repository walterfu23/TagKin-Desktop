import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/content_hash.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/ingest/perceptual_hash.dart';

/// Retries [ItemsRepository.listItems] once when the HTTP connection drops
/// before headers (common during local API restart / `tsx watch`).
@visibleForTesting
Future<List<Item>> listItemsWithRetry(
  ItemsRepository itemsRepository, {
  Duration delay = const Duration(milliseconds: 400),
}) async {
  try {
    return await itemsRepository.listItems();
  } on http.ClientException catch (e) {
    final msg = e.message.toLowerCase();
    final transient = msg.contains('connection closed') ||
        msg.contains('connection reset') ||
        msg.contains('broken pipe');
    if (!transient) rethrow;
    await Future<void>.delayed(delay);
    return itemsRepository.listItems();
  }
}

/// Real folder enumeration — overridable in widget tests so `testWidgets`
/// never drives real `dart:io` filesystem calls through the pumped frame.
final mediaEnumeratorProvider =
    Provider<Future<List<MediaCandidate>> Function(String)>(
  (ref) => enumerateMedia,
);

/// Overridable in widget tests for the same reason as [mediaEnumeratorProvider].
final contentHasherProvider = Provider<Future<String> Function(String)>(
  (ref) => computeContentHash,
);

/// Overridable in widget tests for the same reason as [mediaEnumeratorProvider].
final perceptualHasherProvider = Provider<Future<String?> Function(String)>(
  (ref) => computePerceptualHashFromFile,
);
