import 'package:tagkin_desktop/ingest/media_enumerator.dart';
import 'package:tagkin_desktop/ingest/perceptual_hash.dart';

/// A [MediaCandidate] plus its locally-computed hashes, ready for dedup.
class HashedCandidate {
  const HashedCandidate({
    required this.candidate,
    required this.contentHash,
    this.perceptualHash,
  });

  final MediaCandidate candidate;

  /// Exact-duplicate / idempotency anchor (SHA-256).
  final String contentHash;

  /// Near-duplicate signal (dHash); `null` for video or undecodable photos.
  final String? perceptualHash;
}

/// Why a candidate was excluded from the batch create.
enum SkipReason {
  /// Byte-identical or visually near-identical to another file already
  /// picked as the representative for this batch.
  duplicateInBatch,

  /// `contentHash` already exists in the account's library (fetched via
  /// `GET /items` before dedup) — already ingested in a prior batch.
  existingInLibrary,
}

/// A candidate excluded from creation, with why and (when applicable) which
/// file was kept in its place.
class DedupSkip {
  const DedupSkip({
    required this.candidate,
    required this.reason,
    this.representativePath,
  });

  final HashedCandidate candidate;
  final SkipReason reason;

  /// Path of the file kept instead of [candidate], when [reason] is
  /// [SkipReason.duplicateInBatch].
  final String? representativePath;
}

/// Grouping result: one representative per duplicate/near-duplicate group,
/// plus everything skipped and why.
class DedupResult {
  const DedupResult({required this.representatives, required this.skipped});

  final List<HashedCandidate> representatives;
  final List<DedupSkip> skipped;
}

/// Default dHash Hamming-distance threshold below which two photos are
/// treated as near-duplicates (e.g. burst shots, re-saves). Not part of the
/// API contract — safe to tune without a migration.
const int kDefaultNearDuplicateThreshold = 4;

/// Groups [candidates] into representatives + skips.
///
/// Order of precedence per candidate: already in the account's library
/// ([existingContentHashes]) → exact `contentHash` match to an
/// already-accepted hash in this batch → near-duplicate (dHash Hamming
/// distance ≤ [nearDuplicateHammingThreshold], same [MediaCandidate.type])
/// → otherwise it becomes a new representative. Pure function — no I/O, no
/// network (safe/fast to unit test).
DedupResult dedupCandidates({
  required List<HashedCandidate> candidates,
  Set<String> existingContentHashes = const {},
  int nearDuplicateHammingThreshold = kDefaultNearDuplicateThreshold,
}) {
  final representatives = <HashedCandidate>[];
  final skipped = <DedupSkip>[];
  // Every contentHash seen so far → the representative path covering it,
  // whether it became a representative itself or was folded into a
  // near-duplicate group.
  final hashToRepresentativePath = <String, String>{};

  for (final candidate in candidates) {
    if (existingContentHashes.contains(candidate.contentHash)) {
      skipped.add(
        DedupSkip(candidate: candidate, reason: SkipReason.existingInLibrary),
      );
      continue;
    }

    final knownRepPath = hashToRepresentativePath[candidate.contentHash];
    if (knownRepPath != null) {
      skipped.add(
        DedupSkip(
          candidate: candidate,
          reason: SkipReason.duplicateInBatch,
          representativePath: knownRepPath,
        ),
      );
      continue;
    }

    final nearDupRepPath = candidate.perceptualHash == null
        ? null
        : _findNearDuplicateRepresentative(
            candidate,
            representatives,
            nearDuplicateHammingThreshold,
          );

    if (nearDupRepPath != null) {
      hashToRepresentativePath[candidate.contentHash] = nearDupRepPath;
      skipped.add(
        DedupSkip(
          candidate: candidate,
          reason: SkipReason.duplicateInBatch,
          representativePath: nearDupRepPath,
        ),
      );
      continue;
    }

    hashToRepresentativePath[candidate.contentHash] = candidate.candidate.path;
    representatives.add(candidate);
  }

  return DedupResult(representatives: representatives, skipped: skipped);
}

String? _findNearDuplicateRepresentative(
  HashedCandidate candidate,
  List<HashedCandidate> representatives,
  int threshold,
) {
  for (final rep in representatives) {
    if (rep.perceptualHash == null) continue;
    if (rep.candidate.type != candidate.candidate.type) continue;
    if (hammingDistance(rep.perceptualHash!, candidate.perceptualHash!) <=
        threshold) {
      return rep.candidate.path;
    }
  }
  return null;
}
