import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const kMusicPromptPresetsAsset = 'assets/music_prompt_presets.json';
const kMusicPromptCustomId = 'custom';
const kMusicPromptCustomTitle = 'Custom';

class MusicPromptPreset {
  const MusicPromptPreset({
    required this.id,
    required this.title,
    required this.prompt,
  });

  final String id;
  final String title;
  final String prompt;
}

List<MusicPromptPreset> parseMusicPromptPresets(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List<dynamic>) {
    throw const FormatException('Music prompt catalog must be a JSON array');
  }
  final out = <MusicPromptPreset>[];
  for (final row in decoded) {
    if (row is! Map<String, dynamic>) {
      throw const FormatException('Music prompt row must be an object');
    }
    final id = row['id'];
    final title = row['title'];
    final prompt = row['prompt'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Music prompt id is required');
    }
    if (title is! String || title.isEmpty) {
      throw const FormatException('Music prompt title is required');
    }
    if (prompt is! String || prompt.trim().isEmpty) {
      throw const FormatException('Music prompt text is required');
    }
    out.add(MusicPromptPreset(id: id, title: title, prompt: prompt.trim()));
  }
  return out;
}

Future<List<MusicPromptPreset>> loadMusicPromptPresets() async {
  final file = File('assets/music_prompt_presets.json');
  if (file.existsSync()) {
    return parseMusicPromptPresets(file.readAsStringSync());
  }
  final raw = await rootBundle.loadString(kMusicPromptPresetsAsset);
  return parseMusicPromptPresets(raw);
}
