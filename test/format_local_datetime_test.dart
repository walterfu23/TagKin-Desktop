import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';

void main() {
  const iso = '2026-07-01T12:00:00.000Z';

  test('formatLocalDateTime local has no UTC Z/T', () {
    final shown = formatLocalDateTime(iso);
    expect(shown, isNot(contains('Z')));
    expect(shown, isNot(contains('T')));
    expect(
      shown,
      DateFormat.yMd().add_jms().format(DateTime.parse(iso).toLocal()),
    );
  });

  test('formatLocalDateTime explicit patterns', () {
    final local = DateTime.parse(iso).toLocal();
    expect(
      formatLocalDateTime(iso, format: DateTimeDisplayFormat.mdy12),
      DateFormat('MM/dd/yyyy h:mm:ss a').format(local),
    );
    expect(
      formatLocalDateTime(iso, format: DateTimeDisplayFormat.dmy24),
      DateFormat('dd/MM/yyyy HH:mm:ss').format(local),
    );
    expect(
      formatLocalDateTime(iso, format: DateTimeDisplayFormat.iso24),
      DateFormat('yyyy-MM-dd HH:mm:ss').format(local),
    );
  });

  test('formatLocalDateTime empty/null is em dash; garbage and date-only', () {
    expect(formatLocalDateTime(null), '—');
    expect(formatLocalDateTime(''), '—');
    expect(formatLocalDateTime('   '), '—');
    expect(formatLocalDateTime('summer 2020'), 'summer 2020');
    expect(formatLocalDateTime('2026-07-01'), '2026-07-01');
  });

  test('DateTimeDisplayFormat.parse unknown is local', () {
    expect(DateTimeDisplayFormat.parse(null), DateTimeDisplayFormat.local);
    expect(DateTimeDisplayFormat.parse('nope'), DateTimeDisplayFormat.local);
    expect(DateTimeDisplayFormat.parse('iso24'), DateTimeDisplayFormat.iso24);
  });
}
