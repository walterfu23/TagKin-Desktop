import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/item_lists/music_prompt_presets.dart';

void main() {
  test('music prompt catalog parses five titled prompts', () {
    final raw = File('assets/music_prompt_presets.json').readAsStringSync();
    final presets = parseMusicPromptPresets(raw);
    expect(presets.map((p) => p.id).toList(), [
      'warmFamily',
      'quietPiano',
      'travelOutdoors',
      'kidsPlayful',
      'eveningSentimental',
    ]);
    expect(presets.first.title, 'Warm family');
    expect(presets.first.prompt, contains('Instrumental only'));
    final blob = raw.toLowerCase();
    expect(blob.contains('elevenlabs'), isFalse);
    expect(blob.contains('mubert'), isFalse);
  });
}
