import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/api/jobs_repository.dart';
import 'package:tagkin_desktop/app_shell.dart' show jobsRepositoryProvider;
import 'package:tagkin_desktop/contract/contract.dart';

/// Lifecycle phase of a library export (D7).
enum ExportPhase { idle, running, done, cancelled, error }

/// Writes [LibraryExport] JSON to a user-chosen path. Metadata/refs only —
/// never media bytes (R1/R5/R7).
typedef ExportWriter = Future<String?> Function({
  required String suggestedName,
  required String contents,
});

/// Default writer: native save dialog via [FilePicker], then [File] write.
Future<String?> writeExportToPickedFile({
  required String suggestedName,
  required String contents,
}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export library',
    fileName: suggestedName,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (path == null) return null;
  final file = File(path);
  await file.writeAsString(contents);
  return file.path;
}

/// One-shot `GET /export` + save-to-disk (D7).
class ExportController extends ChangeNotifier {
  ExportController({
    required this.jobsRepository,
    this.writer = writeExportToPickedFile,
  });

  final JobsRepository jobsRepository;
  final ExportWriter writer;

  ExportPhase phase = ExportPhase.idle;
  LibraryExport? lastExport;
  String? savedPath;
  Object? error;

  /// Fetches the library export and prompts the user to save JSON.
  ///
  /// Returns without error when the user cancels the save dialog
  /// ([ExportPhase.cancelled]).
  Future<void> exportLibrary() async {
    if (phase == ExportPhase.running) return;
    phase = ExportPhase.running;
    error = null;
    savedPath = null;
    lastExport = null;
    notifyListeners();

    try {
      final exported = await jobsRepository.exportLibrary();
      lastExport = exported;
      final contents = const JsonEncoder.withIndent('  ').convert(
        exported.toJson(),
      );
      final path = await writer(
        suggestedName: 'tagkin-library-export.json',
        contents: contents,
      );
      if (path == null) {
        phase = ExportPhase.cancelled;
        notifyListeners();
        return;
      }
      savedPath = path;
      phase = ExportPhase.done;
      notifyListeners();
    } catch (e) {
      error = e;
      phase = ExportPhase.error;
      notifyListeners();
    }
  }
}

final exportControllerProvider = Provider.autoDispose<ExportController>(
  (ref) {
    final controller = ExportController(
      jobsRepository: ref.watch(jobsRepositoryProvider),
    );
    ref.onDispose(controller.dispose);
    return controller;
  },
  dependencies: [jobsRepositoryProvider],
);
