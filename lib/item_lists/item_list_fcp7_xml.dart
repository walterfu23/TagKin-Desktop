import 'package:tagkin_desktop/contract/contract.dart' hide ItemListExportFormat;
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/persons/collection.dart';

/// FCP7 XML (xmeml v4). Metadata and local `pathurl`s only — never media bytes (R1).
String itemListToFcp7Xml({
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
  final fileById = {for (final f in timeline.files) f.id: f};
  final writtenFiles = <String>{};
  final xml = ItemListXmlBuf();
  xml.raw('<?xml version="1.0" encoding="UTF-8"?>');
  xml.raw('<!DOCTYPE xmeml>');
  xml.open('<xmeml version="4">');
  // Premiere File > Import looks for a project, not a bare sequence.
  xml.open('<project>');
  xml.line('<name>${xmlEscape(timeline.name)}</name>');
  xml.open('<children>');
  xml.open('<sequence id="sequence-1">');
  xml.line('<name>${xmlEscape(timeline.name)}</name>');
  xml.line('<duration>${timeline.duration}</duration>');
  _rate(xml);
  _timecode(xml);
  xml.open('<media>');
  xml.open('<video>');
  xml.open('<format>');
  xml.open('<samplecharacteristics>');
  xml.line('<width>$sequenceWidth</width>');
  xml.line('<height>$sequenceHeight</height>');
  xml.line('<anamorphic>FALSE</anamorphic>');
  xml.line('<pixelaspectratio>square</pixelaspectratio>');
  xml.line('<fielddominance>none</fielddominance>');
  _rate(xml);
  xml.line('<colordepth>24</colordepth>');
  xml.close('</samplecharacteristics>');
  xml.close('</format>');
  xml.open('<track>');
  final transitionAfter = <int, ItemListNleTransition>{
    for (final t in timeline.transitions) t.afterClipIndex: t,
  };
  final audioClipIndex = <String, int>{};
  var audioN = 0;
  for (final c in timeline.clips) {
    if (!c.isStill) audioClipIndex[c.clipId] = ++audioN;
  }
  final videoClipIndex = {
    for (var i = 0; i < timeline.clips.length; i++)
      timeline.clips[i].clipId: i + 1,
  };
  for (var i = 0; i < timeline.clips.length; i++) {
    final clip = timeline.clips[i];
    final joinAfter = transitionAfter[i];
    final joinBefore = i > 0 ? transitionAfter[i - 1] : null;
    // FCP7: end/start of -1 means “compute from the adjacent transitionitem”.
    _clipItem(
      xml,
      clip: clip,
      file: fileById[clip.fileId]!,
      writtenFiles: writtenFiles,
      audio: false,
      start: joinBefore != null ? -1 : clip.timelineStart,
      end: joinAfter != null ? -1 : clip.timelineEnd,
      videoClipIndex: videoClipIndex[clip.clipId]!,
      audioClipIndex: audioClipIndex[clip.clipId],
      pixels: fileSizesByItemId[clip.entry.itemId],
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
      scaleToFit: scaleToFit,
    );
    if (joinAfter != null) _transitionItem(xml, joinAfter);
  }
  xml.close('</track>');
  xml.close('</video>');
  final audioClips = [for (final c in timeline.clips) if (!c.isStill) c];
  if (audioClips.isNotEmpty) {
    xml.open('<audio>');
    xml.open('<format>');
    xml.open('<samplecharacteristics>');
    xml.line('<depth>16</depth>');
    xml.line('<samplerate>48000</samplerate>');
    xml.close('</samplecharacteristics>');
    xml.close('</format>');
    xml.open('<track>');
    for (final clip in audioClips) {
      _clipItem(
        xml,
        clip: clip,
        file: fileById[clip.fileId]!,
        writtenFiles: writtenFiles,
        audio: true,
        videoClipIndex: videoClipIndex[clip.clipId]!,
        audioClipIndex: audioClipIndex[clip.clipId],
        pixels: fileSizesByItemId[clip.entry.itemId],
        sequenceWidth: sequenceWidth,
        sequenceHeight: sequenceHeight,
        scaleToFit: false,
      );
    }
    xml.close('</track>');
    xml.close('</audio>');
  }
  xml.close('</media>');
  xml.close('</sequence>');
  xml.close('</children>');
  xml.close('</project>');
  xml.close('</xmeml>');
  return xml.toString();
}

void _rate(ItemListXmlBuf xml) {
  xml.open('<rate>');
  xml.line('<timebase>$kItemListNleTimebase</timebase>');
  xml.line('<ntsc>FALSE</ntsc>');
  xml.close('</rate>');
}

void _timecode(ItemListXmlBuf xml) {
  xml.open('<timecode>');
  _rate(xml);
  xml.line('<string>00:00:00:00</string>');
  xml.line('<frame>0</frame>');
  xml.line('<displayformat>NDF</displayformat>');
  xml.close('</timecode>');
}

void _clipItem(
  ItemListXmlBuf xml, {
  required ItemListNleClip clip,
  required ItemListNleFile file,
  required Set<String> writtenFiles,
  required bool audio,
  int? start,
  int? end,
  required int videoClipIndex,
  int? audioClipIndex,
  ItemListPixelSize? pixels,
  required int sequenceWidth,
  required int sequenceHeight,
  required bool scaleToFit,
}) {
  final id = audio ? '${clip.clipId}-audio' : clip.clipId;
  final name = itemListNleFcp7ClipName(clip.entry, clip.localPath);
  final fileId = audio ? '${file.id}-audio' : file.id;
  final sourceDuration = clip.isStill ? 1 : file.durationFrames;
  final sourceIn = clip.isStill ? 0 : clip.sourceIn;
  final sourceOut = clip.isStill ? 1 : clip.sourceOut;
  xml.open('<clipitem id="${xmlEscape(id)}">');
  xml.line('<name>${xmlEscape(name)}</name>');
  xml.line('<enabled>TRUE</enabled>');
  xml.line('<duration>$sourceDuration</duration>');
  _rate(xml);
  xml.line('<start>${start ?? clip.timelineStart}</start>');
  xml.line('<end>${end ?? clip.timelineEnd}</end>');
  xml.line('<in>$sourceIn</in>');
  xml.line('<out>$sourceOut</out>');
  if (clip.isStill && !audio) {
    xml.line('<stillframe>TRUE</stillframe>');
  }
  xml.line('<anamorphic>FALSE</anamorphic>');
  xml.line('<alphatype>none</alphatype>');
  if (writtenFiles.add(fileId)) {
    xml.open('<file id="${xmlEscape(fileId)}">');
    final fileName = itemListNleBasename(file.localPath);
    xml.line(
      '<name>${xmlEscape(fileName.isEmpty ? file.itemId : fileName)}</name>',
    );
    xml.line('<pathurl>${xmlEscape(fcp7PathUrl(file.localPath))}</pathurl>');
    _rate(xml);
    xml.line('<duration>$sourceDuration</duration>');
    xml.open('<media>');
    if (audio) {
      xml.open('<audio>');
      xml.open('<samplecharacteristics>');
      xml.line('<depth>16</depth>');
      xml.line('<samplerate>48000</samplerate>');
      xml.close('</samplecharacteristics>');
      xml.close('</audio>');
    } else {
      xml.open('<video>');
      if (pixels != null && pixels.isValid) {
        xml.open('<samplecharacteristics>');
        xml.line('<width>${pixels.width}</width>');
        xml.line('<height>${pixels.height}</height>');
        xml.close('</samplecharacteristics>');
      }
      xml.close('</video>');
    }
    xml.close('</media>');
    xml.close('</file>');
  } else {
    xml.line('<file id="${xmlEscape(fileId)}"/>');
  }
  if (audio) {
    xml.open('<sourcetrack>');
    xml.line('<mediatype>audio</mediatype>');
    xml.close('</sourcetrack>');
  }
  if (!clip.isStill && audioClipIndex != null) {
    _avLink(
      xml,
      videoId: clip.clipId,
      audioId: '${clip.clipId}-audio',
      videoClipIndex: videoClipIndex,
      audioClipIndex: audioClipIndex,
    );
  }
  if (!audio && scaleToFit && pixels != null && pixels.isValid) {
    final percent = itemListNleFitScalePercent(
      fileWidth: pixels.width,
      fileHeight: pixels.height,
      sequenceWidth: sequenceWidth,
      sequenceHeight: sequenceHeight,
    );
    if (itemListNleNeedsFitScale(percent)) {
      _basicMotionScale(xml, percent);
    }
  }
  final note = itemListNleTagNote(clip.entry);
  if (note.isNotEmpty && !audio) {
    xml.open('<logginginfo>');
    xml.line('<description>${xmlEscape(note)}</description>');
    xml.close('</logginginfo>');
  }
  xml.close('</clipitem>');
}

void _basicMotionScale(ItemListXmlBuf xml, double percent) {
  xml.open('<filter>');
  xml.open('<effect>');
  xml.line('<name>Basic Motion</name>');
  xml.line('<effectid>basic</effectid>');
  xml.line('<effectcategory>motion</effectcategory>');
  xml.line('<effecttype>motion</effecttype>');
  xml.line('<mediatype>video</mediatype>');
  xml.open('<parameter>');
  xml.line('<parameterid>scale</parameterid>');
  xml.line('<name>Scale</name>');
  xml.line('<valuemin>0</valuemin>');
  xml.line('<valuemax>1000</valuemax>');
  xml.line('<value>${itemListNleScaleXmlValue(percent)}</value>');
  xml.close('</parameter>');
  xml.open('<parameter>');
  xml.line('<parameterid>center</parameterid>');
  xml.line('<name>Center</name>');
  xml.open('<value>');
  xml.line('<horiz>0</horiz>');
  xml.line('<vert>0</vert>');
  xml.close('</value>');
  xml.close('</parameter>');
  xml.close('</effect>');
  xml.close('</filter>');
}

void _avLink(
  ItemListXmlBuf xml, {
  required String videoId,
  required String audioId,
  required int videoClipIndex,
  required int audioClipIndex,
}) {
  xml.open('<link>');
  xml.line('<linkclipref>${xmlEscape(videoId)}</linkclipref>');
  xml.line('<mediatype>video</mediatype>');
  xml.line('<trackindex>1</trackindex>');
  xml.line('<clipindex>$videoClipIndex</clipindex>');
  xml.close('</link>');
  xml.open('<link>');
  xml.line('<linkclipref>${xmlEscape(audioId)}</linkclipref>');
  xml.line('<mediatype>audio</mediatype>');
  xml.line('<trackindex>1</trackindex>');
  xml.line('<clipindex>$audioClipIndex</clipindex>');
  xml.close('</link>');
}

void _transitionItem(ItemListXmlBuf xml, ItemListNleTransition join) {
  xml.open('<transitionitem>');
  xml.line('<start>${join.timelineStart}</start>');
  xml.line('<end>${join.timelineEnd}</end>');
  xml.line('<alignment>center</alignment>');
  _rate(xml);
  xml.open('<effect>');
  switch (join.kind) {
    case ExportPhotoTransition.crossDissolve:
      xml.line('<name>Cross Dissolve</name>');
      xml.line('<effectid>Cross Dissolve</effectid>');
    case ExportPhotoTransition.dipToBlack:
    case ExportPhotoTransition.dipToWhite:
      xml.line('<name>Dip to Color Dissolve</name>');
      xml.line('<effectid>Dip to Color Dissolve</effectid>');
    case ExportPhotoTransition.none:
      break;
  }
  xml.line('<effectcategory>Dissolve</effectcategory>');
  xml.line('<effecttype>transition</effecttype>');
  xml.line('<mediatype>video</mediatype>');
  if (join.kind == ExportPhotoTransition.dipToBlack ||
      join.kind == ExportPhotoTransition.dipToWhite) {
    final channel = join.kind == ExportPhotoTransition.dipToWhite ? 255 : 0;
    xml.open('<parameter>');
    xml.line('<parameterid>startcolor</parameterid>');
    xml.line('<name>Start Color</name>');
    _fcp7Color(xml, channel);
    xml.close('</parameter>');
    xml.open('<parameter>');
    xml.line('<parameterid>endcolor</parameterid>');
    xml.line('<name>End Color</name>');
    _fcp7Color(xml, channel);
    xml.close('</parameter>');
  }
  xml.close('</effect>');
  xml.close('</transitionitem>');
}

void _fcp7Color(ItemListXmlBuf xml, int channel) {
  xml.open('<value>');
  xml.line('<alpha>255</alpha>');
  xml.line('<red>$channel</red>');
  xml.line('<green>$channel</green>');
  xml.line('<blue>$channel</blue>');
  xml.close('</value>');
}
