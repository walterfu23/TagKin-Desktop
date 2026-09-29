import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/item_lists/item_list_mp4_render.dart';

void main() {
  const noise =
      '[swscaler @ 0x1] No accelerated colorspace conversion '
      'found from yuv420p to bgr24.\n'
      '[aist#0 @ 0x1] Guessed Channel Layout: stereo\n'
      '[swscaler @ 0x2] deprecated pixel format used, '
      'make sure you did set range correctly\n';

  test('failure sentences name a next step and drop ffmpeg chatter', () {
    final missing = itemListMp4FailureReport(
      step: 'clip 3',
      exitCode: 1,
      stderr: '$noise[in#0] Error opening input: No such file or directory',
      logDir: '/tmp/tagkin-mp4-a',
    );
    expect(missing.sentence, contains('could not be found'));
    expect(missing.sentence, contains('Remove it from the list'));
    expect(missing.technical, isNot(contains('swscaler')));
    expect(missing.technical, isNot(contains('Guessed Channel Layout')));
    expect(missing.technical, isNot(contains('deprecated pixel format')));
    expect(missing.technical, contains('No such file'));

    final disk = itemListMp4FailureReport(
      step: 'assembling',
      exitCode: 1,
      stderr: 'No space left on device',
    );
    expect(disk.sentence, contains('free disk space'));

    final folder = itemListMp4FailureReport(
      step: 'assembling',
      exitCode: 1,
      stderr: 'Permission denied',
    );
    expect(folder.sentence, contains('could not save to that folder'));

    final memory = itemListMp4FailureReport(
      step: 'assembling',
      exitCode: -9,
      stderr: 'Killed',
    );
    expect(memory.sentence, contains('ran out of resources'));

    final music = itemListMp4FailureReport(
      step: 'soundtrack',
      exitCode: 1,
      stderr: '${noise}Invalid data found when processing input',
    );
    expect(music.sentence, contains('could not be read'));
    expect(music.sentence, contains('Generate music again'));
    expect(music.technical, contains('Invalid data'));
    expect(music.technical, isNot(contains('swscaler')));

    final other = itemListMp4FailureReport(
      step: 'assembling',
      exitCode: -22,
      stderr: '${noise}Failed to configure output pad on Parsed_xfade_391',
      logDir: '/tmp/tagkin-mp4-view',
    );
    expect(other.sentence, kItemListMp4FailureGeneric);
    expect(other.sentence, isNot(contains('swscaler')));
    expect(other.technical, contains('Parsed_xfade_391'));
    expect(other.step, 'assembling');
    expect(other.exitCode, -22);
    expect(other.logDir, '/tmp/tagkin-mp4-view');
  });
}
