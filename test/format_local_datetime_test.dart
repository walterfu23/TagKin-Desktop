import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:tagkin_desktop/ui/format_local_datetime.dart';

void main() {
  const iso = '2026-07-01T12:00:00.000Z';
  final local = DateTime.parse(iso).toLocal();
  final zone = local.timeZoneName;

  test('formatLocalDateTime local has no UTC Z/T and appends zone name', () {
    final shown = formatLocalDateTime(iso);
    final formatted = DateFormat.yMd().add_jms().format(local);
    expect(formatted, isNot(contains('Z')));
    expect(formatted, isNot(contains('T')));
    expect(shown, '$formatted $zone');
  });

  test('formatLocalDateTime explicit patterns append zone name', () {
    expect(
      formatLocalDateTime(iso, format: DateTimeDisplayFormat.mdy12),
      '${DateFormat('MM/dd/yyyy h:mm:ss a').format(local)} $zone',
    );
    expect(
      formatLocalDateTime(iso, format: DateTimeDisplayFormat.dmy24),
      '${DateFormat('dd/MM/yyyy HH:mm:ss').format(local)} $zone',
    );
    expect(
      formatLocalDateTime(iso, format: DateTimeDisplayFormat.iso24),
      '${DateFormat('yyyy-MM-dd HH:mm:ss').format(local)} $zone',
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
