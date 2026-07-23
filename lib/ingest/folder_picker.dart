import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';

/// Opens a native "choose folder" dialog; resolves to the picked absolute
/// path, or `null` when the user cancels.
typedef FolderPicker = Future<String?> Function();

/// macOS: NSOpenPanel + security-scoped bookmark persistence.
/// Other platforms: [FilePicker.platform.getDirectoryPath].
Future<String?> pickFolderNative() async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
    final picked = await SecurityScopedBookmarks.pickFolder();
    if (picked == null) return null;
    await folderBookmarkStore.save(picked.path, picked.bookmarkBase64);
    // Keep access alive for the rest of this process (ingest/pre-pass).
    await SecurityScopedBookmarks.startAccess(picked.bookmarkBase64);
    return picked.path;
  }
  return FilePicker.platform.getDirectoryPath();
}

/// Override in widget/integration tests with a fake that returns a fixture
/// path (or `null`, simulating cancel) instead of opening a real native
/// dialog (D3).
final folderPickerProvider = Provider<FolderPicker>((ref) => pickFolderNative);
