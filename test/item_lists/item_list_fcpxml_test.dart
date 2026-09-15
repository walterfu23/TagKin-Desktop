import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/item_lists/item_list_fcpxml.dart';
import 'package:tagkin_desktop/item_lists/item_list_nle.dart';
import 'package:tagkin_desktop/persons/collection.dart';

import '../fake_items_repository.dart';
import 'fake_item_lists_repository.dart';

void main() {
  test('FCPXML 1.9 1080p30 spine matches filmstrip', () {
    final xml = itemListToFcpxml(
      entries: [
        fixtureEntry(
          itemId: 'photo-1',
          who: const ['Sam'],
        ),
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
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
        'video-1': fixtureItem(
          id: 'video-1',
          type: ItemType.video,
          sourceRef: 'file:///Pictures/clip.mp4',
        ),
      },
      description: 'Beach weekend',
    );
    expect(xml, contains('<!DOCTYPE fcpxml>'));
    expect(xml, contains('<fcpxml version="1.9">'));
    expect(xml, contains('name="FFVideoFormat1080p30"'));
    expect(xml, contains('frameDuration="1/30s"'));
    expect(xml, contains('width="1920" height="1080"'));
    expect(xml, contains('<project name="Beach weekend">'));
    expect(xml, contains('src="file:///Pictures/Holiday.jpg"'));
    expect(xml, contains('src="file:///Pictures/clip.mp4"'));
    expect(xml, contains('duration="75/30s"'));
    expect(xml, contains('offset="0s"'));
    expect(xml, contains('start="1s"'));
    expect(xml, contains('duration="3s"'));
    expect(xml, contains('offset="75/30s"'));
    expect(xml, contains('<note>who: Sam</note>'));
    final photo = xml.indexOf('Holiday.jpg');
    final clip = xml.indexOf('clip.mp4');
    expect(photo, lessThan(clip));
  });

  test('two key periods of one video share an asset id', () {
    final xml = itemListToFcpxml(
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
    expect('<asset id="r2"'.allMatches(xml), hasLength(1));
    expect('ref="r2"'.allMatches(xml), hasLength(2));
    expect('file:///Pictures/clip.mp4'.allMatches(xml), hasLength(1));
    expect(xml, contains('hasAudio="1"'));
  });

  test('XML-escapes names and tags', () {
    final xml = itemListToFcpxml(
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
  });

  test('Windows path becomes file:///C:/...', () {
    expect(
      fcpxmlSrc(r'C:\Pictures\Holiday.jpg'),
      'file:///C:/Pictures/Holiday.jpg',
    );
    expect(
      fcpxmlSrc(r'C:\Pictures\Beach weekend.jpg'),
      'file:///C:/Pictures/Beach%20weekend.jpg',
    );
  });

  test('description empty uses view name as project name', () {
    final xml = itemListToFcpxml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/a.jpg',
        ),
      },
      view: const SavedView(
        id: 'v1',
        name: 'Ada',
        filters: LibraryViewFilters(),
      ),
    );
    expect(xml, contains('<project name="Ada">'));
  });

  test('photo still duration follows stillDurationSeconds', () {
    final xml = itemListToFcpxml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      stillDurationSeconds: 5,
    );
    expect(xml, contains('duration="5s"'));
  });

  test('two photos cross-dissolve overlap 1 s', () {
    final xml = itemListToFcpxml(
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
    expect(xml, contains('offset="0s"'));
    expect(xml, contains('duration="75/30s"'));
    expect(
      xml,
      contains(
        '<transition name="Cross Dissolve" offset="45/30s" duration="1s"/>',
      ),
    );
    expect(xml, contains('offset="45/30s"'));
  });

  test('photo then key period is a hard cut', () {
    final xml = itemListToFcpxml(
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
          sourceRef: 'file:///Pictures/Holiday.jpg',
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
    expect(xml, isNot(contains('<transition')));
    expect(xml, contains('offset="75/30s"'));
  });

  test('None keeps photos abutting', () {
    final xml = itemListToFcpxml(
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
    expect(xml, isNot(contains('<transition')));
    expect(xml, contains('offset="75/30s"'));
  });

  test('dip to black and white use Dip to Color', () {
    final black = itemListToFcpxml(
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
    expect(black, contains('name="Dip to Color"'));
    expect(black, contains('value="0 0 0"'));

    final white = itemListToFcpxml(
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
    expect(white, contains('name="Dip to Color"'));
    expect(white, contains('value="1 1 1"'));
  });

  test('1080p sequence uses fit spatialConform and file format size', () {
    final xml = itemListToFcpxml(
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
    expect(xml, contains('name="FFVideoFormat1080p30"'));
    expect(xml, contains('width="4032" height="1816"'));
    expect(xml, contains('spatialConform="fit"'));
  });

  test('unknown still size reuses sequence format', () {
    final xml = itemListToFcpxml(
      entries: [fixtureEntry(itemId: 'photo-1')],
      itemsById: {
        'photo-1': fixtureItem(
          id: 'photo-1',
          sourceRef: 'file:///Pictures/Holiday.jpg',
        ),
      },
      scaleToFit: true,
    );
    expect(xml, contains('format="r1"'));
    expect(xml, isNot(contains('id="fmt-')));
    expect(xml, contains('spatialConform="fit"'));
    expect('width="1920" height="1080"'.allMatches(xml), hasLength(1));
  });

  test('match smallest sequence uses fit spatialConform', () {
    final xml = itemListToFcpxml(
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
    expect(xml, contains('name="FFVideoFormat1080p30"'));
    expect(xml, contains('width="4032" height="1816"'));
    expect(xml, contains('spatialConform="fit"'));
  });

  test('match largest uses none spatialConform', () {
    final xml = itemListToFcpxml(
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
    expect(xml, contains('width="4032" height="1816"'));
    expect(xml, isNot(contains('FFVideoFormat1080p30')));
    expect(xml, contains('spatialConform="none"'));
  });
}
