import 'dart:io';

/// Recursive temp-dir delete with retries.
///
/// Windows CI often hits errno 32 (file in use) if a JSON/jpeg handle has not
/// fully released when [addTearDown] runs.
Future<void> deleteTempDir(Directory dir) async {
  Object? lastError;
  for (var i = 0; i < 12; i++) {
    try {
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
      return;
    } on FileSystemException catch (e) {
      lastError = e;
      await Future<void>.delayed(Duration(milliseconds: 25 * (i + 1)));
    }
  }
  if (lastError != null) {
    Error.throwWithStackTrace(lastError, StackTrace.current);
  }
}
