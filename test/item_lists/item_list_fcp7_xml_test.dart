import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart' hide ItemListExportFormat;
import 'package:tagkin_desktop/item_lists/item_list_fcp7_xml.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/persons/collection.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

void main() {
  test('photo still defaults to 75 frames (2.5 s) at 30 fps', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(
          itemId: 'photo-1',
          who: const ['Sam'],
          what: const ['swimming'],
        ),
      ],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      description: 'Beach weekend',
    );
    expect(xml, contains('<!DOCTYPE xmeml>'));
    expect(xml, contains('<xmeml version="4">'));
    expect(xml, contains('<project>'));
    expect(xml, contains('<children>'));
    expect(xml, contains('<timecode>'));
    expect(xml, contains('<displayformat>NDF</displayformat>'));
    expect(xml, contains('<name>Beach weekend</name>'));
    expect(xml, contains('<stillframe>TRUE</stillframe>'));
    expect(xml, contains('<enabled>TRUE</enabled>'));
    expect(xml, contains('<width>1920</width>'));
    expect(xml, contains('<height>1080</height>'));
    expect(xml, contains('<start>0</start>'));
    expect(xml, contains('<end>75</end>'));
    expect(xml, contains('<in>0</in>'));
    expect(xml, contains('<out>1</out>'));
    expect(xml, contains('<duration>1</duration>'));
    expect(xml, contains('<timebase>30</timebase>'));
    expect(
      xml,
      contains('<pathurl>file://localhost///Pictures/Holiday.jpg</pathurl>'),
    );
    expect(
      xml,
      contains('<description>who: Sam; what: swimming</description>'),
    );
  });

  test('photo still duration follows stillDurationSeconds', () {
    final xml = itemListToFcp7Xml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      stillDurationSeconds: 5,
    );
    expect(xml, contains('<end>150</end>'));
    expect(xml, contains('<out>1</out>'));
    expect(xml, isNot(contains('<out>150</out>')));
  });

  test('key period in/out are frames at 30 fps', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(
          itemId: 'video-1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp-1',
          startMs: 1000,
          endMs: 4000,
        ),
      ],
      itemsById: {
        'video-1': fixtureItem(
          id: 'video-1',
          type: ItemType.video,
          sourceRef: 'file:///Pictures/clip.mp4',
        ),
      },
    );
    expect(xml, contains('<in>30</in>'));
    expect(xml, contains('<out>120</out>'));
    expect(xml, contains('<start>0</start>'));
    expect(xml, contains('<end>90</end>'));
    expect(xml, isNot(contains('<stillframe>')));
    expect(xml, contains('<mediatype>audio</mediatype>'));
    expect(xml, contains('<file id="file-1-audio">'));
    expect(xml, contains('<linkclipref>clipitem-1</linkclipref>'));
    expect(xml, contains('<linkclipref>clipitem-1-audio</linkclipref>'));
    expect(xml, contains('clip.mp4 0:01-0:04'));
    expect(xml, isNot(contains('–')));
    expect(
      xml,
      contains('<pathurl>file://localhost///Pictures/clip.mp4</pathurl>'),
    );
  });

  test('two key periods of one video share a file id', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(
          itemId: 'video-1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp-1',
          startMs: 1000,
          endMs: 4000,
        ),
        fixtureEntry(
          itemId: 'video-1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp-2',
          startMs: 5000,
          endMs: 8000,
        ),
      ],
      itemsById: {
        'video-1': fixtureItem(
          id: 'video-1',
          type: ItemType.video,
          sourceRef: 'file:///Pictures/clip.mp4',
        ),
      },
    );
    expect('<file id="file-1">'.allMatches(xml), hasLength(1));
    expect('<file id="file-1"/>'.allMatches(xml), isNotEmpty);
    expect('<file id="file-1-audio">'.allMatches(xml), hasLength(1));
    expect('<file id="file-1-audio"/>'.allMatches(xml), isNotEmpty);
    expect(
      'file://localhost///Pictures/clip.mp4'.allMatches(xml),
      hasLength(2),
    );
    expect(xml, contains('<start>0</start>'));
    expect(xml, contains('<end>90</end>'));
    expect(xml, contains('<start>90</start>'));
    expect(xml, contains('<end>180</end>'));
  });

  test('filmstrip order and view name when description is empty', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(itemId: 'photo-b'),
        fixtureEntry(itemId: 'photo-a'),
      ],
      itemsById: {
        'photo-a': fixtureItem(
          id: 'photo-a',
          sourceRef: 'file:///Pictures/a.jpg',
        ),
        'photo-b': fixtureItem(
          id: 'photo-b',
          sourceRef: 'file:///Pictures/b.jpg',
        ),
      },
      view: const SavedView(id: 'v1', name: 'Ada', filters: LibraryViewFilters()),
    );
    expect(xml, contains('<name>Ada</name>'));
    final b = xml.indexOf('b.jpg');
    final a = xml.indexOf('a.jpg');
    expect(b, lessThan(a));
  });

  test('XML-escapes names and tags', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(
          itemId: 'photo-1',
          who: const ['Sam & Ada'],
          what: const ['a <swim>'],
        ),
      ],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/A&B.jpg',
        ),
      },
    );
    expect(xml, contains('Sam &amp; Ada'));
    expect(xml, contains('a &lt;swim&gt;'));
    expect(xml, contains('A&amp;B.jpg'));
    expect(xml, isNot(contains('Sam & Ada')));
  });

  test('Windows path becomes file://localhost///C:/...', () {
    expect(
      fcp7PathUrl(r'C:\Pictures\Holiday.jpg'),
      'file://localhost///C:/Pictures/Holiday.jpg',
    );
    expect(
      fcp7PathUrl(r'C:\Pictures\Beach weekend.jpg'),
      'file://localhost///C:/Pictures/Beach%20weekend.jpg',
    );
  });

  test('default sequence name is Item list', () {
    final xml = itemListToFcp7Xml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(id: 'photo-1', sourceRef: 'file:///a.jpg'),
      },
    );
    expect(xml, contains('<name>Item list</name>'));
  });

  test('two photos cross-dissolve overlap 1 s (30 frames)', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(itemId: 'photo-a'),
        fixtureEntry(itemId: 'photo-b'),
      ],
      itemsById: {
        'photo-a': fixtureItem(
          id: 'photo-a',
          sourceRef: 'file:///Pictures/a.jpg',
        ),
        'photo-b': fixtureItem(
          id: 'photo-b',
          sourceRef: 'file:///Pictures/b.jpg',
        ),
      },
      transition: ExportPhotoTransition.crossDissolve,
      transitionSeconds: 1,
    );
    expect(xml, contains('<start>0</start>'));
    expect(xml, contains('<end>-1</end>'));
    expect(xml, contains('<start>-1</start>'));
    expect(xml, contains('<end>120</end>'));
    expect(xml, contains('<start>45</start>'));
    expect(xml, contains('<end>75</end>'));
    expect('<transitionitem>'.allMatches(xml), hasLength(1));
    expect(xml, contains('<name>Cross Dissolve</name>'));
    expect(xml, contains('<effectid>Cross Dissolve</effectid>'));
  });

  test('photo then key period is a hard cut', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(itemId: 'photo-1'),
        fixtureEntry(
          itemId: 'video-1',
          kind: ItemListEntryKind.keyperiod,
          keyPeriodId: 'kp-1',
          startMs: 1000,
          endMs: 4000,
        ),
      ],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/a.jpg',
        ),
        'video-1': fixtureItem(
          id: 'video-1',
          type: ItemType.video,
          sourceRef: 'file:///Pictures/clip.mp4',
        ),
      },
      transition: ExportPhotoTransition.crossDissolve,
      transitionSeconds: 1,
    );
    expect(xml, isNot(contains('<transitionitem>')));
    expect(xml, isNot(contains('<end>-1</end>')));
    expect(xml, isNot(contains('<start>-1</start>')));
    expect(xml, contains('<start>0</start>'));
    expect(xml, contains('<end>75</end>'));
    expect(xml, contains('<start>75</start>'));
    expect(xml, contains('<end>165</end>'));
    expect(xml, contains('<out>1</out>'));
    expect(xml, contains('<linkclipref>clipitem-2</linkclipref>'));
    expect(xml, contains('<linkclipref>clipitem-2-audio</linkclipref>'));
    expect(xml, contains('<clipindex>2</clipindex>'));
    expect(xml, contains('<clipindex>1</clipindex>'));
  });

  test('None keeps photos abutting', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(itemId: 'photo-a'),
        fixtureEntry(itemId: 'photo-b'),
      ],
      itemsById: {
        'photo-a': fixtureItem(
          id: 'photo-a',
          sourceRef: 'file:///Pictures/a.jpg',
        ),
        'photo-b': fixtureItem(
          id: 'photo-b',
          sourceRef: 'file:///Pictures/b.jpg',
        ),
      },
      transition: ExportPhotoTransition.none,
    );
    expect(xml, isNot(contains('<transitionitem>')));
    expect(xml, isNot(contains('<end>-1</end>')));
    expect(xml, isNot(contains('<start>-1</start>')));
    expect(xml, contains('<start>0</start>'));
    expect(xml, contains('<end>75</end>'));
    expect(xml, contains('<start>75</start>'));
    expect(xml, contains('<end>150</end>'));
  });

  test('dip to black and white use Dip to Color Dissolve', () {
    final black = itemListToFcp7Xml(
      entries: [
        fixtureEntry(itemId: 'photo-a'),
        fixtureEntry(itemId: 'photo-b'),
      ],
      itemsById: {
        'photo-a': fixtureItem(
          id: 'photo-a',
          sourceRef: 'file:///Pictures/a.jpg',
        ),
        'photo-b': fixtureItem(
          id: 'photo-b',
          sourceRef: 'file:///Pictures/b.jpg',
        ),
      },
      transition: ExportPhotoTransition.dipToBlack,
      transitionSeconds: 1,
    );
    expect(black, contains('<name>Dip to Color Dissolve</name>'));
    expect(black, contains('<red>0</red>'));
    expect(black, isNot(contains('<red>255</red>')));

    final white = itemListToFcp7Xml(
      entries: [
        fixtureEntry(itemId: 'photo-a'),
        fixtureEntry(itemId: 'photo-b'),
      ],
      itemsById: {
        'photo-a': fixtureItem(
          id: 'photo-a',
          sourceRef: 'file:///Pictures/a.jpg',
        ),
        'photo-b': fixtureItem(
          id: 'photo-b',
          sourceRef: 'file:///Pictures/b.jpg',
        ),
      },
      transition: ExportPhotoTransition.dipToWhite,
      transitionSeconds: 1,
    );
    expect(white, contains('<name>Dip to Color Dissolve</name>'));
    expect(white, contains('<red>255</red>'));
  });

  test('transition overlap clamps to still length minus one frame', () {
    final xml = itemListToFcp7Xml(
      entries: [
        fixtureEntry(itemId: 'photo-a'),
        fixtureEntry(itemId: 'photo-b'),
      ],
      itemsById: {
        'photo-a': fixtureItem(
          id: 'photo-a',
          sourceRef: 'file:///Pictures/a.jpg',
        ),
        'photo-b': fixtureItem(
          id: 'photo-b',
          sourceRef: 'file:///Pictures/b.jpg',
        ),
      },
      stillDurationSeconds: 0.5,
      transition: ExportPhotoTransition.crossDissolve,
      transitionSeconds: 2,
    );
    expect(xml, contains('<start>0</start>'));
    expect(xml, contains('<end>-1</end>'));
    expect(xml, contains('<start>-1</start>'));
    expect(xml, contains('<end>16</end>'));
    expect(xml, contains('<start>1</start>'));
    expect(xml, contains('<end>15</end>'));
  });

  test('1080p sequence scales a larger still to fit', () {
    final xml = itemListToFcp7Xml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      fileSizesByItemId: const {
        'photo-1': ItemListPixelSize(4032, 1816),
      },
      scaleToFit: true,
    );
    expect(xml, contains('<width>1920</width>'));
    expect(xml, contains('<height>1080</height>'));
    expect(xml, contains('<width>4032</width>'));
    expect(xml, contains('<height>1816</height>'));
    expect(xml, contains('<effectid>basic</effectid>'));
    expect(xml, contains('<parameterid>scale</parameterid>'));
    expect(xml, contains('<value>47.619</value>'));
  });

  test('match smallest sequence scales a larger still to fit', () {
    final xml = itemListToFcp7Xml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      sequenceWidth: 1920,
      sequenceHeight: 1080,
      fileSizesByItemId: const {
        'photo-1': ItemListPixelSize(4032, 1816),
      },
      scaleToFit: true,
    );
    expect(xml, contains('<width>1920</width>'));
    expect(xml, contains('<height>1080</height>'));
    expect(xml, contains('<width>4032</width>'));
    expect(xml, contains('<height>1816</height>'));
    expect(xml, contains('<effectid>basic</effectid>'));
    expect(xml, contains('<value>47.619</value>'));
  });

  test('unknown still size does not fake sequence pixels or Fit scale', () {
    final xml = itemListToFcp7Xml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      scaleToFit: true,
    );
    expect('<width>1920</width>'.allMatches(xml), hasLength(1));
    expect('<height>1080</height>'.allMatches(xml), hasLength(1));
    expect(xml, isNot(contains('<effectid>basic</effectid>')));
  });

  test('match largest sequence uses photo pixels and does not scale', () {
    final xml = itemListToFcp7Xml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      sequenceWidth: 4032,
      sequenceHeight: 1816,
      fileSizesByItemId: const {
        'photo-1': ItemListPixelSize(4032, 1816),
      },
    );
    expect(xml, contains('<width>4032</width>'));
    expect(xml, contains('<height>1816</height>'));
    expect(xml, isNot(contains('<effectid>basic</effectid>')));
  });
}
