import 'package:tagkin_desktop/contract/contract.dart' hide ItemListExportFormat;
import 'package:tagkin_desktop/item_lists/export_photo_transition.dart';
import 'package:tagkin_desktop/item_lists/item_list_csv.dart';
import 'package:tagkin_desktop/persons/collection.dart';
import 'package:tagkin_desktop/review/local_media_resolver.dart';

export 'package:tagkin_desktop/item_lists/export_photo_transition.dart';
export 'package:tagkin_desktop/item_lists/export_sequence_size.dart';
export 'package:tagkin_desktop/item_lists/item_list_media_size.dart'
    show
        ItemListPixelSize,
        kItemListNle1080p,
        kItemListNle4k,
        itemListNleSequencePixelSize,
        itemListNleFitScalePercent,
        itemListNleNeedsFitScale,
        itemListNleScaleXmlValue;

/// Item-list NLE interchange: 30 fps non-drop.
const kItemListNleTimebase = 30;
const kItemListNleStillDurationSeconds = 2.5;
const kItemListNleTransitionSeconds = 1.0;
const kItemListNleWidth = 1920;
const kItemListNleHeight = 1080;

enum ItemListExportFormat {
  json,
  fcp7Xml,
  fcpxml,
  mp4WithMusic;

  String get label => switch (this) {
        json => 'JSON',
        fcp7Xml => 'FCP7 XML',
        fcpxml => 'FCPXML',
        mp4WithMusic => 'MP4 (with music)',
      };

  String get fileExtension => switch (this) {
        json => 'json',
        fcp7Xml => 'xml',
        fcpxml => 'fcpxml',
        mp4WithMusic => 'mp4',
      };
}

int itemListNleStillDurationMs({
  double stillDurationSeconds = kItemListNleStillDurationSeconds,
}) {
  final ms = (stillDurationSeconds * 1000).round();
  return ms < 1 ? 1 : ms;
}

int itemListNleStillDurationFrames({
  double stillDurationSeconds = kItemListNleStillDurationSeconds,
}) =>
    itemListNleDurationFrames(
      startMs: 0,
      endMs: itemListNleStillDurationMs(
        stillDurationSeconds: stillDurationSeconds,
      ),
    );

/// Timeline or source position in frames. Zero stays zero.
int itemListNleMsToFrames(int ms) {
  if (ms <= 0) return 0;
  return (ms * kItemListNleTimebase / 1000).round();
}

/// Clip length in frames; at least one frame when bounds collapse.
int itemListNleDurationFrames({required int startMs, required int endMs}) {
  final d = itemListNleMsToFrames(endMs) - itemListNleMsToFrames(startMs);
  return d < 1 ? 1 : d;
}

/// Photo-to-photo overlap in frames. Zero when [transition] is None or a
/// still is too short to leave one uncovered frame on each side.
int itemListNleTransitionOverlapFrames({
  required ExportPhotoTransition transition,
  required double transitionSeconds,
  required int leftDurationFrames,
  required int rightDurationFrames,
}) {
  if (transition == ExportPhotoTransition.none) return 0;
  final requested = itemListNleStillDurationFrames(
    stillDurationSeconds: transitionSeconds,
  );
  final maxOverlap = (leftDurationFrames < rightDurationFrames
          ? leftDurationFrames
          : rightDurationFrames) -
      1;
  if (maxOverlap < 1) return 0;
  return requested > maxOverlap ? maxOverlap : requested;
}

String itemListNleSequenceName({
  required String description,
  SavedView? view,
}) {
  final trimmed = description.trim();
  if (trimmed.isNotEmpty) return trimmed;
  final viewName = view?.name.trim();
  if (viewName != null && viewName.isNotEmpty) return viewName;
  return 'Item list';
}

String itemListNleBasename(String? localPath) {
  if (localPath == null || localPath.isEmpty) return '';
  final posix = localPath.replaceAll('\\', '/');
  final slash = posix.lastIndexOf('/');
  return slash < 0 ? posix : posix.substring(slash + 1);
}

String itemListNleClipName(ItemListEntry entry, String? localPath) {
  final base = itemListNleBasename(localPath);
  final name = base.isEmpty ? entry.itemId : base;
  if (entry.kind != ItemListEntryKind.keyperiod) return name;
  final start = formatKeyPeriodMs(entry.startMs ?? 0);
  final end = formatKeyPeriodMs(entry.endMs ?? 0);
  return '$name $start–$end';
}

/// FCP7 clip names: ASCII hyphen so Premiere File → Import does not abort.
String itemListNleFcp7ClipName(ItemListEntry entry, String? localPath) {
  return itemListNleClipName(entry, localPath).replaceAll('–', '-');
}

String itemListNleTagNote(ItemListEntry entry) {
  final parts = <String>[];
  if (entry.who.isNotEmpty) parts.add('who: ${entry.who.join(', ')}');
  if (entry.what.isNotEmpty) parts.add('what: ${entry.what.join(', ')}');
  if (entry.where.isNotEmpty) parts.add('where: ${entry.where.join(', ')}');
  return parts.join('; ');
}

String xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String? itemListNleLocalPath(
  ItemListEntry entry,
  Map<String, Item> itemsById,
) {
  return localPathFromSourceRef(itemsById[entry.itemId]?.sourceRef);
}

/// POSIX path with a leading slash (Windows `C:` → `/C:`).
String itemListNlePosixPath(String localPath) {
  var posix = localPath.replaceAll('\\', '/');
  if (!posix.startsWith('/')) posix = '/$posix';
  return posix;
}

String itemListNleEncodePath(String posixPath) {
  return posixPath.split('/').map((seg) {
    if (seg.isEmpty) return '';
    return Uri.encodeComponent(seg)
        .replaceAll('%3A', ':')
        .replaceAll('%3a', ':');
  }).join('/');
}

/// FCP7 `pathurl`: `file://localhost///Users/...` or `file://localhost///C:/...`.
String fcp7PathUrl(String? localPath) {
  if (localPath == null || localPath.isEmpty) return '';
  return 'file://localhost//${itemListNleEncodePath(itemListNlePosixPath(localPath))}';
}

/// FCPXML `src`: RFC 8089 `file:///Users/...` or `file:///C:/...`.
String fcpxmlSrc(String? localPath) {
  if (localPath == null || localPath.isEmpty) return '';
  return 'file://${itemListNleEncodePath(itemListNlePosixPath(localPath))}';
}

/// FCPXML time: whole seconds as `Ns`, otherwise `N/30s`.
String fcpxmlTime(int frames) {
  if (frames % kItemListNleTimebase == 0) {
    return '${frames ~/ kItemListNleTimebase}s';
  }
  return '$frames/${kItemListNleTimebase}s';
}

class ItemListNleClip {
  const ItemListNleClip({
    required this.entry,
    required this.localPath,
    required this.fileId,
    required this.clipId,
    required this.timelineStart,
    required this.timelineDuration,
    required this.sourceIn,
    required this.sourceOut,
    required this.isStill,
  });

  final ItemListEntry entry;
  final String? localPath;
  final String fileId;
  final String clipId;
  final int timelineStart;
  final int timelineDuration;
  final int sourceIn;
  final int sourceOut;
  final bool isStill;

  int get timelineEnd => timelineStart + timelineDuration;
}

class ItemListNleFile {
  const ItemListNleFile({
    required this.id,
    required this.itemId,
    required this.localPath,
    required this.isStill,
    required this.durationFrames,
  });

  final String id;
  final String itemId;
  final String? localPath;
  final bool isStill;
  final int durationFrames;
}

class ItemListNleTransition {
  const ItemListNleTransition({
    required this.afterClipIndex,
    required this.timelineStart,
    required this.durationFrames,
    required this.kind,
  });

  /// Clip that ends into this join (`clips[afterClipIndex]`).
  final int afterClipIndex;
  final int timelineStart;
  final int durationFrames;
  final ExportPhotoTransition kind;

  int get timelineEnd => timelineStart + durationFrames;
}

class ItemListNleTimeline {
  const ItemListNleTimeline({
    required this.name,
    required this.clips,
    required this.files,
    required this.duration,
    this.transitions = const [],
  });

  final String name;
  final List<ItemListNleClip> clips;
  final List<ItemListNleFile> files;
  final int duration;
  final List<ItemListNleTransition> transitions;
}

ItemListNleTimeline itemListNleTimeline({
  required List<ItemListEntry> entries,
  required Map<String, Item> itemsById,
  SavedView? view,
  String description = '',
  double stillDurationSeconds = kItemListNleStillDurationSeconds,
  ExportPhotoTransition transition = ExportPhotoTransition.crossDissolve,
  double transitionSeconds = kItemListNleTransitionSeconds,
}) {
  final stillFrames = itemListNleStillDurationFrames(
    stillDurationSeconds: stillDurationSeconds,
  );
  final fileIdByItem = <String, String>{};
  final maxOutByItem = <String, int>{};
  final stillByItem = <String, bool>{};
  final pathByItem = <String, String?>{};
  var fileN = 1;
  for (final e in entries) {
    final id = fileIdByItem.putIfAbsent(e.itemId, () => 'file-$fileN');
    if (id == 'file-$fileN') fileN++;
    final isStill = e.kind != ItemListEntryKind.keyperiod;
    stillByItem[e.itemId] = isStill;
    pathByItem[e.itemId] = itemListNleLocalPath(e, itemsById);
    final out = isStill ? stillFrames : itemListNleMsToFrames(e.endMs ?? 0);
    final prev = maxOutByItem[e.itemId] ?? 0;
    if (out > prev) maxOutByItem[e.itemId] = out;
  }

  final files = [
    for (final itemId in fileIdByItem.keys)
      ItemListNleFile(
        id: fileIdByItem[itemId]!,
        itemId: itemId,
        localPath: pathByItem[itemId],
        isStill: stillByItem[itemId] ?? true,
        durationFrames: maxOutByItem[itemId] ?? stillFrames,
      ),
  ];

  var t = 0;
  var clipN = 1;
  final clips = <ItemListNleClip>[];
  final transitions = <ItemListNleTransition>[];
  for (final e in entries) {
    final isStill = e.kind != ItemListEntryKind.keyperiod;
    final sourceIn = isStill ? 0 : itemListNleMsToFrames(e.startMs ?? 0);
    final duration = isStill
        ? stillFrames
        : itemListNleDurationFrames(
            startMs: e.startMs ?? 0,
            endMs: e.endMs ?? 0,
          );
    var start = t;
    if (clips.isNotEmpty && clips.last.isStill && isStill) {
      final overlap = itemListNleTransitionOverlapFrames(
        transition: transition,
        transitionSeconds: transitionSeconds,
        leftDurationFrames: clips.last.timelineDuration,
        rightDurationFrames: duration,
      );
      if (overlap > 0) {
        start = clips.last.timelineEnd - overlap;
        transitions.add(
          ItemListNleTransition(
            afterClipIndex: clips.length - 1,
            timelineStart: start,
            durationFrames: overlap,
            kind: transition,
          ),
        );
      }
    }
    clips.add(
      ItemListNleClip(
        entry: e,
        localPath: pathByItem[e.itemId],
        fileId: fileIdByItem[e.itemId]!,
        clipId: 'clipitem-$clipN',
        timelineStart: start,
        timelineDuration: duration,
        sourceIn: sourceIn,
        sourceOut: sourceIn + duration,
        isStill: isStill,
      ),
    );
    t = start + duration;
    clipN++;
  }

  return ItemListNleTimeline(
    name: itemListNleSequenceName(description: description, view: view),
    clips: clips,
    files: files,
    duration: t,
    transitions: transitions,
  );
}

/// Timeline length in milliseconds (30 fps).
int itemListNleTimelineDurationMs(ItemListNleTimeline timeline) {
  if (timeline.duration <= 0) return 0;
  return (timeline.duration * 1000 / kItemListNleTimebase).round();
}

/// Indenting XML writer for FCP7 / FCPXML (no extra package).
class ItemListXmlBuf {
  final StringBuffer _buf = StringBuffer();
  int _indent = 0;

  void raw(String line) => _buf.writeln(line);

  void line(String line) {
    _buf.writeln('${'  ' * _indent}$line');
  }

  void open(String tag) {
    line(tag);
    _indent++;
  }

  void close(String tag) {
    _indent--;
    line(tag);
  }

  @override
  String toString() => _buf.toString();
}
