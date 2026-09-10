import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tagkin_desktop/contract/contract.dart';
import 'package:tagkin_desktop/library/processing_status_view.dart';

void main() {
  test('ProcessingStatusView maps every enum value to a distinct label', () {
    final labels = <String>{};
    for (final status in ProcessingStatus.values) {
      final view = ProcessingStatusView.of(status);
      expect(view.label, isNotEmpty);
      expect(view.label.contains(status.wire.split('_').first), isTrue,
          reason: '${status.wire} label should reflect wire name');
      labels.add(view.label);
    }
    expect(labels.length, ProcessingStatus.values.length);
  });

  test('each ProcessingStatus has a non-null icon and color', () {
    for (final status in ProcessingStatus.values) {
      final view = ProcessingStatusView.of(status);
      expect(view.icon, isNotNull);
      expect(view.color, isNotNull);
    }
  });

  test('wire labels cover pending → tagged → failed → cancelled', () {
    expect(
      ProcessingStatusView.of(ProcessingStatus.pending).label,
      'pending',
    );
    expect(
      ProcessingStatusView.of(ProcessingStatus.awaitingModelAccess).label,
      'awaiting model access',
    );
    expect(
      ProcessingStatusView.of(ProcessingStatus.processing).label,
      'processing',
    );
    expect(
      ProcessingStatusView.of(ProcessingStatus.tagged).label,
      'tagged',
    );
    expect(
      ProcessingStatusView.of(ProcessingStatus.failed).label,
      'failed',
    );
    expect(
      ProcessingStatusView.of(ProcessingStatus.cancelled).label,
      'cancelled',
    );
  });

  testWidgets('failed badge tooltip shows processingError', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProcessingStatusBadge(
            status: ProcessingStatus.failed,
            processingError: 'provider boom',
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('processing-status-error-tooltip')), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(
      find.byKey(const Key('processing-status-error-tooltip')),
    );
    expect(tooltip.message, 'provider boom');
  });

  testWidgets('non-failed badge has no error tooltip', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProcessingStatusBadge(
            status: ProcessingStatus.tagged,
            processingError: 'stale',
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('processing-status-error-tooltip')), findsNothing);
  });
}
