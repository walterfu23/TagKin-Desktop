import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:tagkin_desktop/contract/contract.dart' hide ItemListExportFormat;
import 'package:tagkin_desktop/ingest/folder_bookmark_store.dart';
import 'package:tagkin_desktop/ingest/model_upload_image.dart';
import 'package:tagkin_desktop/ingest/upload_mime.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';

class ItemListMp4RenderException implements Exception {
  ItemListMp4RenderException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Thrown when the user leaves Export list and cancels an in-flight encode.
class ItemListMp4CancelledException extends ItemListMp4RenderException {
  ItemListMp4CancelledException() : super('MP4 export was cancelled.');
}

/// Decode stills ffmpeg cannot read (HEIC/HEIF, …) to JPEG bytes.
typedef ItemListMp4StillToJpeg = Future<Uint8List?> Function(Uint8List bytes);

/// True when a still must be re-encoded to JPEG before ffmpeg (not JPEG/PNG).
bool itemListMp4StillNeedsJpeg(String path) {
  final mime = mimeTypeForPath(path, ItemType.photo);
  return mime != 'image/jpeg' && mime != 'image/png';
}

/// Copy/convert unique clip files into [destDir] so ffmpeg can read them.
///
/// macOS App Sandbox does not grant the ffmpeg child process access to
/// security-scoped library folders; Dart reads while the bookmark is live
/// and writes sandbox-readable copies. HEIC/HEIF (and other non-JPEG/PNG
/// stills) become JPEG via [stillToJpeg].
Future<Map<String, String>> itemListMaterializeMp4Inputs({
  required Iterable<ItemListNleClip> clips,
  required String destDir,
  FolderBookmarkStore? bookmarks,
  Future<void> Function(String bookmark)? startAccess,
  ItemListMp4StillToJpeg? stillToJpeg,
}) async {
  final convert = stillToJpeg ?? convertHeicLikeToJpeg;
  final byOriginal = <String, String>{};
  var n = 0;
  for (final clip in clips) {
    final original = clip.localPath;
    if (original == null || original.isEmpty) {
      throw ItemListMp4RenderException('Missing local file for a clip');
    }
    if (byOriginal.containsKey(original)) continue;
    await _ensureBookmarkAccess(
      sourcePath: original,
      bookmarks: bookmarks,
      startAccess: startAccess,
    );
    final src = File(original);
    if (!src.existsSync()) {
      throw ItemListMp4RenderException(
        'A photo or video on this list is missing ($original).',
      );
    }
    final dest = p.join(
      destDir,
      _materializedName(
        index: n,
        original: original,
        asJpeg: clip.isStill && itemListMp4StillNeedsJpeg(original),
      ),
    );
    n++;
    try {
      if (clip.isStill && itemListMp4StillNeedsJpeg(original)) {
        final jpeg = await convert(await src.readAsBytes());
        if (jpeg == null || jpeg.isEmpty) {
          throw ItemListMp4RenderException(
            'Could not decode a still for MP4 export ($original).',
          );
        }
        await File(dest).writeAsBytes(jpeg, flush: true);
      } else {
        await src.copy(dest);
      }
    } on ItemListMp4RenderException {
      rethrow;
    } catch (e) {
      throw ItemListMp4RenderException(
        'Could not read a photo or video for MP4 export ($original): $e',
      );
    }
    final out = File(dest);
    if (!out.existsSync() || out.lengthSync() == 0) {
      throw ItemListMp4RenderException(
        'Could not stage a photo or video for MP4 export ($original).',
      );
    }
    byOriginal[original] = dest;
  }
  return byOriginal;
}

/// Same timeline with clip/file [localPath]s rewritten to materialized copies.
ItemListNleTimeline itemListMp4TimelineWithMaterializedPaths(
  ItemListNleTimeline timeline,
  Map<String, String> byOriginal,
) {
  String? rewrite(String? path) {
    if (path == null || path.isEmpty) return path;
    return byOriginal[path] ?? path;
  }

  return ItemListNleTimeline(
    name: timeline.name,
    duration: timeline.duration,
    transitions: timeline.transitions,
    clips: [
      for (final c in timeline.clips)
        ItemListNleClip(
          entry: c.entry,
          localPath: rewrite(c.localPath),
          fileId: c.fileId,
          clipId: c.clipId,
          timelineStart: c.timelineStart,
          timelineDuration: c.timelineDuration,
          sourceIn: c.sourceIn,
          sourceOut: c.sourceOut,
          isStill: c.isStill,
        ),
    ],
    files: [
      for (final f in timeline.files)
        ItemListNleFile(
          id: f.id,
          itemId: f.itemId,
          localPath: rewrite(f.localPath),
          isStill: f.isStill,
          durationFrames: f.durationFrames,
        ),
    ],
  );
}

/// Same timeline with each clip pointing at a pre-encoded `clip-N.mp4`.
ItemListNleTimeline itemListMp4TimelineWithClipVideos(
  ItemListNleTimeline timeline,
  List<String> clipPaths,
) {
  if (clipPaths.length != timeline.clips.length) {
    throw ItemListMp4RenderException(
      'clip count ${clipPaths.length} != timeline ${timeline.clips.length}',
    );
  }
  return ItemListNleTimeline(
    name: timeline.name,
    duration: timeline.duration,
    transitions: timeline.transitions,
    clips: [
      for (var i = 0; i < timeline.clips.length; i++)
        ItemListNleClip(
          entry: timeline.clips[i].entry,
          localPath: clipPaths[i],
          fileId: timeline.clips[i].fileId,
          clipId: timeline.clips[i].clipId,
          timelineStart: timeline.clips[i].timelineStart,
          timelineDuration: timeline.clips[i].timelineDuration,
          sourceIn: 0,
          sourceOut: timeline.clips[i].timelineDuration,
          isStill: timeline.clips[i].isStill,
        ),
    ],
    files: [
      for (var i = 0; i < timeline.clips.length; i++)
        ItemListNleFile(
          id: timeline.clips[i].fileId,
          itemId: timeline.clips[i].entry.itemId,
          localPath: clipPaths[i],
          isStill: timeline.clips[i].isStill,
          durationFrames: timeline.clips[i].timelineDuration,
        ),
    ],
  );
}

String _materializedName({
  required int index,
  required String original,
  required bool asJpeg,
}) {
  final ext = asJpeg ? '.jpg' : p.extension(original);
  final safeExt = ext.isEmpty ? '' : ext.toLowerCase();
  return 'in-$index$safeExt';
}

Future<void> _ensureBookmarkAccess({
  required String sourcePath,
  FolderBookmarkStore? bookmarks,
  Future<void> Function(String bookmark)? startAccess,
}) async {
  if (!SecurityScopedBookmarks.isSupported) return;
  final store = bookmarks ?? folderBookmarkStore;
  final start = startAccess ?? SecurityScopedBookmarks.startAccess;
  final bookmark = await store.bookmarkForFile(sourcePath);
  if (bookmark == null) return;
  try {
    await start(bookmark);
  } catch (_) {}
}
