final class LocalDate {
  const LocalDate({required this.year, required this.month, required this.day});

  factory LocalDate.parse(String value) {
    final RegExpMatch? match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})$',
    ).firstMatch(value);
    if (match == null) {
      throw FormatException('Expected YYYY-MM-DD', value);
    }
    return LocalDate(
      year: int.parse(match.group(1)!),
      month: int.parse(match.group(2)!),
      day: int.parse(match.group(3)!),
    );
  }

  final int year;
  final int month;
  final int day;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is LocalDate &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

final class LocalTime {
  const LocalTime({
    required this.hour,
    required this.minute,
    required this.second,
  });

  factory LocalTime.parse(String value) {
    final RegExpMatch? match = RegExp(
      r'^(\d{2}):(\d{2}):(\d{2})$',
    ).firstMatch(value);
    if (match == null) {
      throw FormatException('Expected HH:mm:ss', value);
    }
    return LocalTime(
      hour: int.parse(match.group(1)!),
      minute: int.parse(match.group(2)!),
      second: int.parse(match.group(3)!),
    );
  }

  final int hour;
  final int minute;
  final int second;

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is LocalTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

final class UtcInstant {
  UtcInstant(DateTime value) : value = value.toUtc();

  factory UtcInstant.parse(String value) {
    final DateTime parsed = DateTime.parse(value);
    if (!value.endsWith('Z')) {
      throw FormatException('Expected an RFC 3339 UTC instant', value);
    }
    return UtcInstant(parsed);
  }

  final DateTime value;

  @override
  String toString() => value.toIso8601String();

  @override
  bool operator ==(Object other) => other is UtcInstant && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class IsoDuration {
  const IsoDuration(this.value);

  factory IsoDuration.parse(String value) {
    if (!RegExp(r'^P(?=\d|T\d)').hasMatch(value)) {
      throw FormatException('Expected an ISO 8601 duration', value);
    }
    return IsoDuration(value);
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

final class IanaTimezone {
  const IanaTimezone._(this.value);

  factory IanaTimezone.parse(String value) {
    if (!RegExp(r'^[A-Za-z_]+(?:/[A-Za-z0-9_+\-]+)+$').hasMatch(value)) {
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

final class TemporalCodec {
  const TemporalCodec();

  String encodeDate(LocalDate value) => value.toString();
  LocalDate decodeDate(String value) => LocalDate.parse(value);
  String encodeTime(LocalTime value) => value.toString();
  LocalTime decodeTime(String value) => LocalTime.parse(value);
  String encodeInstant(UtcInstant value) => value.toString();
  UtcInstant decodeInstant(String value) => UtcInstant.parse(value);
  String encodeDuration(IsoDuration value) => value.toString();
  IsoDuration decodeDuration(String value) => IsoDuration.parse(value);
  String encodeTimezone(IanaTimezone value) => value.toString();
  IanaTimezone decodeTimezone(String value) => IanaTimezone.parse(value);
}
