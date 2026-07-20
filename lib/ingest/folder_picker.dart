import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens a native "choose folder" dialog; resolves to the picked absolute
/// path, or `null` when the user cancels.
typedef FolderPicker = Future<String?> Function();

Future<String?> pickFolderNative() => FilePicker.platform.getDirectoryPath();

/// Override in widget/integration tests with a fake that returns a fixture
/// path (or `null`, simulating cancel) instead of opening a real native
/// dialog (D3).
final folderPickerProvider = Provider<FolderPicker>((ref) => pickFolderNative);
