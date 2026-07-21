import 'iana_zones.dart';

final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _timePattern = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$');
final RegExp _instantPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$',
);
final RegExp _durationPattern = RegExp(
  r'^P(?=\d|T\d)(?:(?:\d+(?:[.,]\d+)?Y)?(?:\d+(?:[.,]\d+)?M)?(?:\d+(?:[.,]\d+)?W)?(?:\d+(?:[.,]\d+)?D)?)(?:T(?=\d)(?:\d+(?:[.,]\d+)?H)?(?:\d+(?:[.,]\d+)?M)?(?:\d+(?:[.,]\d+)?S)?)?$',
);

/// A C0 `YYYY-MM-DD` calendar date.
final class WireDate {
  const WireDate._(this.year, this.month, this.day);

  factory WireDate(int year, int month, int day) {
    _validateDate(year, month, day, '$year-$month-$day');
    return WireDate._(year, month, day);
  }

  factory WireDate.parse(String value) {
    final RegExpMatch? match = _datePattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Expected YYYY-MM-DD', value);
    }
    final int year = int.parse(match.group(1)!);
    final int month = int.parse(match.group(2)!);
    final int day = int.parse(match.group(3)!);
    _validateDate(year, month, day, value);
    return WireDate._(year, month, day);
  }

  final int year;
  final int month;
  final int day;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is WireDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

/// A C0 `HH:mm:ss` local wall-clock time.
final class WireTime {
  const WireTime._(this.hour, this.minute, this.second);

  factory WireTime(int hour, int minute, int second) {
    _validateTime(hour, minute, second, '$hour:$minute:$second');
    return WireTime._(hour, minute, second);
  }

  factory WireTime.parse(String value) {
    final RegExpMatch? match = _timePattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Expected HH:mm:ss', value);
    }
    final int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2)!);
    final int second = int.parse(match.group(3)!);
    _validateTime(hour, minute, second, value);
    return WireTime._(hour, minute, second);
  }

  final int hour;
  final int minute;
  final int second;

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is WireTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

/// A validated ISO 8601 duration preserved without lossy conversion.
final class IsoDuration {
  const IsoDuration._(this.value);

  factory IsoDuration.parse(String value) {
    if (!_durationPattern.hasMatch(value)) {
      throw FormatException('Expected an ISO 8601 duration', value);
    }
    return IsoDuration._(value.replaceAll(',', '.'));
  }

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is IsoDuration && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// A validated IANA timezone identifier.
///
/// Validation is exact membership in the IANA time zone database release
/// bundled as [ianaTimeZoneRelease] (see `iana_zones.dart`), not a lexical
/// shape check. Canonical zones (`Asia/Singapore`), aliases, the `Etc/*`
/// family, and the bare `UTC` identifier are accepted; offsets (`+08:00`),
/// abbreviations, path-traversal components (`Area/../Location`), and unknown
/// names (`Area/NotAnIanaZone`) are rejected.
final class IanaTimezone {
  const IanaTimezone._(this.value);

  factory IanaTimezone.parse(String value) {
    if (!isIanaTimeZone(value)) {
      throw FormatException('Expected an IANA timezone identifier', value);
    }
    return IanaTimezone._(value);
  }

  final String value;

  @override
  String toString() => value;

  @override
  bool operator ==(Object other) =>
      other is IanaTimezone && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// Formats [value] as a canonical RFC 3339 UTC instant ending in `Z`.
String formatRfc3339Utc(DateTime value) {
  final DateTime utc = value.toUtc();
  _validateDate(utc.year, utc.month, utc.day, utc.toString());
  return utc.toIso8601String();
}

/// Parses a strict RFC 3339 UTC instant.
DateTime parseRfc3339Utc(String value) {
  final RegExpMatch? match = _instantPattern.firstMatch(value);
  if (match == null) {
    throw FormatException('Expected an RFC 3339 UTC instant', value);
  }
  _validateDate(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    value,
  );
  _validateTime(
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
    value,
  );
  final DateTime parsed = DateTime.parse(value);
  return parsed.toUtc();
}

/// Codec facade for all C0 temporal wire forms.
final class WireCodec {
  const WireCodec();

  String encodeDate(WireDate value) => value.toString();
  WireDate decodeDate(String value) => WireDate.parse(value);
  String encodeTime(WireTime value) => value.toString();
  WireTime decodeTime(String value) => WireTime.parse(value);
  String encodeInstant(DateTime value) => formatRfc3339Utc(value);
  DateTime decodeInstant(String value) => parseRfc3339Utc(value);
  String encodeDuration(IsoDuration value) => value.toString();
  IsoDuration decodeDuration(String value) => IsoDuration.parse(value);
  String encodeTimezone(IanaTimezone value) => value.toString();
  IanaTimezone decodeTimezone(String value) => IanaTimezone.parse(value);
}

void _validateDate(int year, int month, int day, String source) {
  if (year < 1 || year > 9999) {
    throw FormatException('Expected a valid calendar date', source);
  }
  final DateTime date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    throw FormatException('Expected a valid calendar date', source);
  }
}

void _validateTime(int hour, int minute, int second, String source) {
  if (hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59 ||
      second < 0 ||
      second > 59) {
    throw FormatException('Expected a valid wall-clock time', source);
  }
}
