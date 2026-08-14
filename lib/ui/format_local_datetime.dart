import 'package:intl/intl.dart';

/// How the UI renders UTC ISO timestamps in the device timezone.
enum DateTimeDisplayFormat {
  /// OS locale date + time with seconds (default).
  local,
  /// `MM/dd/yyyy h:mm:ss a`
  mdy12,
  /// `dd/MM/yyyy HH:mm:ss`
  dmy24,
  /// `yyyy-MM-dd HH:mm:ss`
  iso24;

  String get wire => name;

  String get settingsLabel => switch (this) {
        DateTimeDisplayFormat.local => 'Local (this computer)',
        DateTimeDisplayFormat.mdy12 => 'MM/dd/yyyy h:mm:ss a',
        DateTimeDisplayFormat.dmy24 => 'dd/MM/yyyy HH:mm:ss',
        DateTimeDisplayFormat.iso24 => 'yyyy-MM-dd HH:mm:ss',
      };

  static DateTimeDisplayFormat parse(Object? value) {
    final s = value is String ? value : null;
    return DateTimeDisplayFormat.values
            .where((f) => f.wire == s)
            .firstOrNull ??
        DateTimeDisplayFormat.local;
  }
}

/// Format an API UTC ISO-8601 timestamp for display in the device timezone.
///
/// Wire values stay UTC (`…Z`). Date-only `yyyy-MM-dd` is left as a calendar
/// date (no UTC-midnight shift). Empty/null → [empty]. Unparseable → original.
String formatLocalDateTime(
  String? iso, {
  String empty = '—',
  DateTimeDisplayFormat format = DateTimeDisplayFormat.local,
}) {
  if (iso == null || iso.trim().isEmpty) return empty;
  final trimmed = iso.trim();
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return trimmed;
  final dt = DateTime.tryParse(trimmed);
  if (dt == null) return iso;
  return _formatter(format).format(dt.toLocal());
}

DateFormat _formatter(DateTimeDisplayFormat format) {
  switch (format) {
    case DateTimeDisplayFormat.local:
      return DateFormat.yMd().add_jms();
    case DateTimeDisplayFormat.mdy12:
      return DateFormat('MM/dd/yyyy h:mm:ss a');
    case DateTimeDisplayFormat.dmy24:
      return DateFormat('dd/MM/yyyy HH:mm:ss');
    case DateTimeDisplayFormat.iso24:
      return DateFormat('yyyy-MM-dd HH:mm:ss');
  }
}
