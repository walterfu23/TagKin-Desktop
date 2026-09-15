import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/persons/collection.dart';

/// FCPXML 1.9. Metadata and local `src` URLs only — never media bytes (R1).
String itemListToFcpxml({
  required List<ItemListEntry> entries,
  required Map<String, Item> itemsById,
  SavedView? view,
  String description = '',
  double stillDurationSeconds = kItemListNleStillDurationSeconds,
  ExportPhotoTransition transition = ExportPhotoTransition.crossDissolve,
  double transitionSeconds = kItemListNleTransitionSeconds,
  int sequenceWidth = kItemListNleWidth,
  int sequenceHeight = kItemListNleHeight,
  Map<String, ItemListPixelSize> fileSizesByItemId = const {},
  bool scaleToFit = false,
}) {
  final timeline = itemListNleTimeline(
    entries: entries,
    itemsById: itemsById,
    view: view,
    description: description,
    stillDurationSeconds: stillDurationSeconds,
    transition: transition,
    transitionSeconds: transitionSeconds,
  );
  final assetIdByFileId = <String, String>{};
  var assetN = 2;
  for (final file in timeline.files) {
    assetIdByFileId[file.id] = 'r$assetN';
    assetN++;
  }

  final xml = ItemListXmlBuf();
  xml.raw('<?xml version="1.0" encoding="UTF-8"?>');
  xml.raw('<!DOCTYPE fcpxml>');
  xml.open('<fcpxml version="1.9">');
  xml.open('<resources>');
  xml.line(_fcpxmlFormatLine(
    id: 'r1',
    width: sequenceWidth,
    height: sequenceHeight,
  ));
  final formatIdByFileId = <String, String>{};
  for (final file in timeline.files) {
    final pixels = fileSizesByItemId[file.itemId];
    if (pixels != null && pixels.isValid) {
      xml.line(_fcpxmlFormatLine(
        id: 'fmt-${file.id}',
        width: pixels.width,
        height: pixels.height,
      ));
      formatIdByFileId[file.id] = 'fmt-${file.id}';
    } else {
      formatIdByFileId[file.id] = 'r1';
    }
  }
  for (final file in timeline.files) {
    final assetId = assetIdByFileId[file.id]!;
    final name = itemListNleBasename(file.localPath);
    final display = name.isEmpty ? file.itemId : name;
    final hasAudio = file.isStill ? '' : ' hasAudio="1"';
    xml.line(
      '<asset id="${xmlEscape(assetId)}" name="${xmlEscape(display)}" '
      'src="${xmlEscape(fcpxmlSrc(file.localPath))}" start="0s" '
      'duration="${fcpxmlTime(file.durationFrames)}" hasVideo="1"$hasAudio '
      'format="${formatIdByFileId[file.id]}"/>',
    );
  }
  xml.close('</resources>');
  xml.open('<library>');
  xml.open('<event name="${xmlEscape(timeline.name)}">');
  xml.open('<project name="${xmlEscape(timeline.name)}">');
  xml.open(
    '<sequence format="r1" tcStart="0s" tcFormat="NDF" '
    'duration="${fcpxmlTime(timeline.duration)}">',
  );
  xml.open('<spine>');
  final transitionAfter = <int, ItemListNleTransition>{
    for (final t in timeline.transitions) t.afterClipIndex: t,
  };
  for (var i = 0; i < timeline.clips.length; i++) {
    final clip = timeline.clips[i];
    final assetId = assetIdByFileId[clip.fileId]!;
    final name = itemListNleClipName(clip.entry, clip.localPath);
    final note = itemListNleTagNote(clip.entry);
    final startAttr = clip.sourceIn == 0
        ? ''
        : ' start="${fcpxmlTime(clip.sourceIn)}"';
    final spatial = scaleToFit
        ? ' spatialConform="fit"'
        : ' spatialConform="none"';
    xml.open(
      '<asset-clip ref="${xmlEscape(assetId)}" name="${xmlEscape(name)}" '
      'offset="${fcpxmlTime(clip.timelineStart)}" '
      'duration="${fcpxmlTime(clip.timelineDuration)}"$startAttr$spatial>',
    );
    if (note.isNotEmpty) {
      xml.line('<note>${xmlEscape(note)}</note>');
    }
    xml.close('</asset-clip>');
    final join = transitionAfter[i];
    if (join != null) _transition(xml, join);
  }
  xml.close('</spine>');
  xml.close('</sequence>');
  xml.close('</project>');
  xml.close('</event>');
  xml.close('</library>');
  xml.close('</fcpxml>');
  return xml.toString();
}

String _fcpxmlFormatLine({
  required String id,
  required int width,
  required int height,
}) {
  final name = width == 1920 && height == 1080
      ? ' name="FFVideoFormat1080p30"'
      : width == 3840 && height == 2160
          ? ' name="FFVideoFormat2160p30"'
          : '';
  return '<format id="$id"$name '
      'frameDuration="1/${kItemListNleTimebase}s" '
      'width="$width" height="$height"/>';
}

void _transition(ItemListXmlBuf xml, ItemListNleTransition join) {
  final offset = fcpxmlTime(join.timelineStart);
  final duration = fcpxmlTime(join.durationFrames);
  switch (join.kind) {
    case ExportPhotoTransition.crossDissolve:
      xml.line(
        '<transition name="Cross Dissolve" offset="$offset" '
        'duration="$duration"/>',
      );
    case ExportPhotoTransition.dipToBlack:
    case ExportPhotoTransition.dipToWhite:
      final color =
          join.kind == ExportPhotoTransition.dipToWhite ? '1 1 1' : '0 0 0';
      xml.open(
        '<transition name="Dip to Color" offset="$offset" '
        'duration="$duration">',
      );
      xml.line('<param name="Color" value="$color"/>');
      xml.close('</transition>');
    case ExportPhotoTransition.none:
      break;
  }
}
