// Person-link verification: one iteration of delete-all → re-analyze ×N → link.
//
// Invoked by mac/12_person_link_loop.sh via:
//   flutter run -d macos -t tool/person_link_loop.dart
//
// Env (required):
//   TAGKIN_API_TOKEN          Bearer JWT
//   TAGKIN_LOOP_ITEM_IDS      comma-separated item UUIDs (expect 3)
// Optional:
//   TAGKIN_API_URL            default http://localhost:8787
//
// Success when one person has appearances on every loop item.
// Prints a line `PERSON_LINK_LOOP_RESULT:ok|fail|error …` for the shell to parse.
// Never prints the bearer token. Never confirms persons (R6).

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tagkin_desktop/api/api_client.dart';
import 'package:tagkin_desktop/api/items_repository.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/api/persons_repository.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/persons/who_face_linker.dart';
import 'package:tagkin_desktop/prepass/onnx_face_embedder.dart';

const _resultPrefix = 'PERSON_LINK_LOOP_RESULT:';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    final result = await runPersonLinkIteration();
    final line = result.ok
        ? '${_resultPrefix}ok persons=${result.personCount}'
        : '${_resultPrefix}fail persons=${result.personCount} '
            'ids=${result.personIds.join(',')}';
    stdout.writeln(result.summary);
    stdout.writeln(line);
    await _writeStatusBestEffort(line);
    exit(result.ok ? 0 : 1);
  } catch (e, st) {
    final line = '${_resultPrefix}error $e';
    stderr.writeln('person_link_loop failed: $e\n$st');
    stdout.writeln(line);
    await _writeStatusBestEffort(line);
    exit(2);
  }
}

/// App sandbox cannot write host /tmp from the shell's mktemp — use app support.
Future<void> _writeStatusBestEffort(String line) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'person_link_loop.status'));
    await file.writeAsString(line, flush: true);
  } catch (_) {
    // stdout sentinel is enough for the shell wrapper.
  }
}

class PersonLinkIterationResult {
  const PersonLinkIterationResult({
    required this.ok,
    required this.personCount,
    required this.personIds,
    required this.summary,
  });

  final bool ok;
  final int personCount;
  final List<String> personIds;
  final String summary;
}

Future<PersonLinkIterationResult> runPersonLinkIteration() async {
  final token = Platform.environment['TAGKIN_API_TOKEN']?.trim() ?? '';
  if (token.isEmpty) {
    throw StateError('TAGKIN_API_TOKEN is required');
  }
  final idsRaw = Platform.environment['TAGKIN_LOOP_ITEM_IDS']?.trim() ?? '';
  final itemIds = idsRaw
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (itemIds.length < 2) {
    throw StateError(
      'TAGKIN_LOOP_ITEM_IDS must list at least 2 item UUIDs (want 3)',
    );
  }
  final baseUrl = (Platform.environment['TAGKIN_API_URL'] ??
          'http://localhost:8787')
      .replaceAll(RegExp(r'/+$'), '');

  final client = ApiClient(
    baseUrl: baseUrl,
    tokenProvider: () => token,
  );
  final persons = PersonsRepository(client);
  final items = ItemsRepository(client);
  final jobs = JobsRepository(client);

  stdout.writeln('==> delete all persons');
  final existing = await persons.listPersons();
  for (final p in existing) {
    stdout.writeln('    DELETE person ${p.id}');
    await persons.deletePerson(p.id);
  }

  final onnx = await OnnxFaceEmbedder.tryCreate();
  if (onnx == null) {
    throw StateError(
      'ONNX face embedder unavailable — run mac/117_fetch_face_models.sh '
      'and ensure assets/models/*.onnx exist',
    );
  }
  final linker = WhoFaceLinker(items: items, embedder: onnx);

  for (final id in itemIds) {
    stdout.writeln('==> analyze $id');
    final analyzed = await jobs.analyzeItem(id);
    if (analyzed.item.type != ItemType.photo) {
      throw StateError('item $id is not a photo');
    }
    stdout.writeln('==> who-face link $id');
    final linked = await linker.linkWhoFacesForItem(analyzed.item);
    if (linked == null) {
      stdout.writeln(
        '    warning: no who-appearances posted (no who regions or stub skip)',
      );
    } else {
      stdout.writeln(
        '    appearances=${linked.appearances.length}',
      );
    }
  }

  await onnx.dispose();

  // Success = one person spans every loop item (same face across photos).
  // Extra persons from other people in group shots are OK — counting total
  // persons==1 fails on multi-who photos even when matching works (v5
  // distances ~0.28–0.31 for the shared subject).
  final after = await persons.listPersons();
  final ids = after.map((p) => p.id).toList();
  String? consolidatedId;
  final coverage = <String, Set<String>>{};
  for (final p in after) {
    final detail = await persons.getPerson(p.id);
    final covered = detail.appearances
        .map((a) => a.itemId)
        .whereType<String>()
        .toSet();
    coverage[p.id] = covered;
    if (itemIds.every(covered.contains)) {
      consolidatedId = p.id;
      break;
    }
  }
  final ok = consolidatedId != null;
  final summary = ok
      ? 'PASS: cross-item person=$consolidatedId '
          'covers ${itemIds.length} items '
          '(persons_total=${after.length})'
      : 'FAIL: no person covers all ${itemIds.length} items '
          '(persons_total=${after.length}) '
          'coverage=${coverage.entries.map((e) => '${e.key}:${e.value.length}').join(';')} '
          'ids=${ids.join(',')}';

  client.close();
  return PersonLinkIterationResult(
    ok: ok,
    personCount: after.length,
    personIds: ids,
    summary: summary,
  );
}
