import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';

/// Opens a native "choose folder" dialog; resolves to the picked absolute
/// path, or `null` when the user cancels.
typedef FolderPicker = Future<String?> Function();

/// macOS sandbox / missing-folder failure while resuming ingest.
class FolderAccessException implements Exception {
  FolderAccessException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Restore read access before scan/hash/upload (crash resume).
///
/// macOS: start the persisted security-scoped bookmark. Windows: folder
/// must still exist. Returns the sandbox-resolved path to enumerate (may
/// differ from [folderPath] on macOS).
Future<String?> ensureIngestFolderAccess(String folderPath) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    final bookmark = await folderBookmarkStore.bookmarkForFile(folderPath);
    if (bookmark == null) {
      throw FolderAccessException(
        'Add this folder again to continue ingest.',
      );
    }
    final resolved = await SecurityScopedBookmarks.startAccess(bookmark);
    if (resolved.isNotEmpty && resolved != folderPath) {
      await folderBookmarkStore.save(resolved, bookmark);
    }
    return resolved.isNotEmpty ? resolved : folderPath;
  }
  if (!Directory(folderPath).existsSync()) {
    throw FolderAccessException(
      'Add this folder again to continue ingest.',
    );
  }
  return folderPath;
}

/// macOS: NSOpenPanel + security-scoped bookmark persistence.
/// Other platforms: [FilePicker.platform.getDirectoryPath].
Future<String?> pickFolderNative() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    final picked = await SecurityScopedBookmarks.pickFolder();
    if (picked == null) return null;
    final resolved = await SecurityScopedBookmarks.startAccess(
      picked.bookmarkBase64,
    );
    await folderBookmarkStore.save(picked.path, picked.bookmarkBase64);
    if (resolved.isNotEmpty && resolved != picked.path) {
      await folderBookmarkStore.save(resolved, picked.bookmarkBase64);
    }
    return resolved.isNotEmpty ? resolved : picked.path;
  }
  return FilePicker.platform.getDirectoryPath();
}

/// Override in widget/integration tests with a fake that returns a fixture
/// path (or `null`, simulating cancel) instead of opening a real native
/// dialog (D3).
final folderPickerProvider = Provider<FolderPicker>((ref) => pickFolderNative);
