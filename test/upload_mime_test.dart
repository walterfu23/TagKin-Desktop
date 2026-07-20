import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/ingest/upload_mime.dart';

void main() {
  test('mimeTypeForPath maps photo extensions', () {
    expect(mimeTypeForPath('/a/b.jpg', ItemType.photo), 'image/jpeg');
    expect(mimeTypeForPath('/a/b.JPEG', ItemType.photo), 'image/jpeg');
    expect(mimeTypeForPath('/a/b.png', ItemType.photo), 'image/png');
    expect(mimeTypeForPath('/a/b.heic', ItemType.photo), 'image/heic');
  });

  test('mimeTypeForPath maps video extensions', () {
    expect(mimeTypeForPath('/a/b.mp4', ItemType.video), 'video/mp4');
    expect(mimeTypeForPath('/a/b.mov', ItemType.video), 'video/quicktime');
  });

  test('frame sample jpg is always image/jpeg', () {
    expect(
      mimeTypeForPath('/tmp/tagkin_frames_/frame_0000.jpg', ItemType.video),
      'image/jpeg',
    );
  });

  test('unknown extension falls back by ItemType', () {
    expect(mimeTypeForPath('/a/b.bin', ItemType.photo), 'image/jpeg');
    expect(mimeTypeForPath('/a/b.bin', ItemType.video), 'video/mp4');
  });
}
