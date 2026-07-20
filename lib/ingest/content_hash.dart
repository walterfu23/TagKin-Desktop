import 'dart:io';

import 'package:crypto/crypto.dart';

/// SHA-256 content hash of a local file — the exact-duplicate / idempotency
/// anchor sent as `Item.contentHash` (never the bytes themselves, R1/R7).
/// Reads only from local disk; never touches the network.
Future<String> computeContentHash(String path) async {
  final bytes = await File(path).readAsBytes();
  return sha256.convert(bytes).toString();
}
