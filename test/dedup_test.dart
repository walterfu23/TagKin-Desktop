import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/dedup.dart';
import 'package:tagkin_desktop/ingest/media_enumerator.dart';

HashedCandidate _photo(
  String path, {
  required String contentHash,
  String? perceptualHash,
}) {
  return HashedCandidate(
    candidate: MediaCandidate(
      path: path,
      type: ItemType.photo,
      size: 100,
      modifiedAt: DateTime(2026, 1, 1),
    ),
    contentHash: contentHash,
    perceptualHash: perceptualHash,
  );
}

HashedCandidate _video(String path, {required String contentHash}) {
  return HashedCandidate(
    candidate: MediaCandidate(
      path: path,
      type: ItemType.video,
      size: 100,
      modifiedAt: DateTime(2026, 1, 1),
    ),
    contentHash: contentHash,
  );
}

void main() {
  group('dedupCandidates', () {
    test('byte-identical files collapse to one representative', () {
      final result = dedupCandidates(
        candidates: [
          _photo('/a.jpg', contentHash: 'hash1', perceptualHash: '0' * 16),
          _photo('/b.jpg', contentHash: 'hash1', perceptualHash: '0' * 16),
        ],
      );

      expect(result.representatives, hasLength(1));
      expect(result.representatives.single.candidate.path, '/a.jpg');
      expect(result.skipped, hasLength(1));
      expect(result.skipped.single.reason, SkipReason.duplicateInBatch);
      expect(result.skipped.single.representativePath, '/a.jpg');
    });

    test(
        'near-duplicate photos (low Hamming distance) collapse to one representative',
        () {
      final result = dedupCandidates(
        candidates: [
          _photo('/a.jpg', contentHash: 'hashA', perceptualHash: '0000000000000000'),
          _photo('/b.jpg', contentHash: 'hashB', perceptualHash: '0000000000000001'),
        ],
        nearDuplicateHammingThreshold: 4,
      );

      expect(result.representatives, hasLength(1));
      expect(result.representatives.single.candidate.path, '/a.jpg');
      expect(result.skipped.single.reason, SkipReason.duplicateInBatch);
      expect(result.skipped.single.representativePath, '/a.jpg');
    });

    test('visually distinct photos both become representatives', () {
      final result = dedupCandidates(
        candidates: [
          _photo('/a.jpg', contentHash: 'hashA', perceptualHash: '0000000000000000'),
          _photo('/b.jpg', contentHash: 'hashB', perceptualHash: 'ffffffffffffffff'),
        ],
        nearDuplicateHammingThreshold: 4,
      );

      expect(result.representatives, hasLength(2));
      expect(result.skipped, isEmpty);
    });

    test('a hash already in the account library is skipped, not created', () {
      final result = dedupCandidates(
        candidates: [_photo('/a.jpg', contentHash: 'already-there')],
        existingContentHashes: {'already-there'},
      );

      expect(result.representatives, isEmpty);
      expect(result.skipped.single.reason, SkipReason.existingInLibrary);
    });

    test('videos are never merged by perceptual hash (photo-only in D3)', () {
      final result = dedupCandidates(
        candidates: [
          _video('/a.mp4', contentHash: 'hashA'),
          _video('/b.mp4', contentHash: 'hashB'),
        ],
      );

      expect(result.representatives, hasLength(2));
    });

    test('a photo and a video are never cross-type merged', () {
      final result = dedupCandidates(
        candidates: [
          _photo('/a.jpg', contentHash: 'hashA', perceptualHash: '0000000000000000'),
          _video('/a.mp4', contentHash: 'hashB'),
        ],
      );
      expect(result.representatives, hasLength(2));
    });

    test(
        'an exact duplicate of an already-folded near-duplicate resolves to the same representative',
        () {
      // b is a near-duplicate of a (folded into a's group); c is
      // byte-identical to b and must also resolve to a, not to b.
      final result = dedupCandidates(
        candidates: [
          _photo('/a.jpg', contentHash: 'hashA', perceptualHash: '0000000000000000'),
          _photo('/b.jpg', contentHash: 'hashB', perceptualHash: '0000000000000001'),
          _photo('/c.jpg', contentHash: 'hashB', perceptualHash: '0000000000000001'),
        ],
      );

      expect(result.representatives, hasLength(1));
      expect(result.representatives.single.candidate.path, '/a.jpg');
      expect(result.skipped, hasLength(2));
      for (final skip in result.skipped) {
        expect(skip.representativePath, '/a.jpg');
      }
    });
  });
}
