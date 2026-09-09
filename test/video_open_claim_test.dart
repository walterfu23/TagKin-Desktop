import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/review/video_open_claim.dart';

void main() {
  group('VideoOpenClaim', () {
    test('claim returns true for a fresh path', () {
      final claim = VideoOpenClaim();
      expect(claim.claim('/a.mp4'), isTrue);
      expect(claim.isCurrent('/a.mp4'), isTrue);
    });

    test('re-claiming the same path while current returns false', () {
      final claim = VideoOpenClaim();
      expect(claim.claim('/a.mp4'), isTrue);
      expect(claim.claim('/a.mp4'), isFalse);
      expect(claim.isCurrent('/a.mp4'), isTrue);
    });

    test('isCurrent is false for the old path after a different path is claimed',
        () {
      final claim = VideoOpenClaim();
      expect(claim.claim('/a.mp4'), isTrue);
      expect(claim.claim('/b.mp4'), isTrue);
      expect(claim.isCurrent('/a.mp4'), isFalse);
      expect(claim.isCurrent('/b.mp4'), isTrue);
    });

    test('clear lets the same path be claimed again', () {
      final claim = VideoOpenClaim();
      expect(claim.claim('/a.mp4'), isTrue);
      claim.clear();
      expect(claim.isCurrent('/a.mp4'), isFalse);
      expect(claim.claim('/a.mp4'), isTrue);
    });
  });
}
