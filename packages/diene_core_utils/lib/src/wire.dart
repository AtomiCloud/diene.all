/// C0 §1 temporal wire forms: ISO 8601 / RFC 3339 dates, times, instants,
/// durations, and IANA timezone identifiers.
///
/// Every parse is a total function returning `Result`: a malformed wire string
/// yields an `invalid_format` [Problem] naming the expected grammar and the
/// rejected value, never a thrown `FormatException`. Constructors that could
/// fail are exposed as static `of`/`parse` members rather than Dart factory
/// constructors, because a factory constructor cannot return a `Result`.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

import 'iana_zones.dart';
import 'util_problem.dart';

final RegExp _datePattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
final RegExp _timePattern = RegExp(r'^(\d{2}):(\d{2}):(\d{2})$');
final RegExp _instantPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?Z$',
);
final RegExp _durationPattern = RegExp(
  r'^P(?=\d|T\d)(?:(?:\d+(?:[.,]\d+)?Y)?(?:\d+(?:[.,]\d+)?M)?(?:\d+(?:[.,]\d+)?W)?(?:\d+(?:[.,]\d+)?D)?)(?:T(?=\d)(?:\d+(?:[.,]\d+)?H)?(?:\d+(?:[.,]\d+)?M)?(?:\d+(?:[.,]\d+)?S)?)?$',
);

/// The C0 wire grammar for a calendar date.
const String wireDateGrammar = 'a YYYY-MM-DD calendar date';

/// The C0 wire grammar for a wall-clock time.
const String wireTimeGrammar = 'an HH:mm:ss wall-clock time';

/// The C0 wire grammar for an instant.
const String wireInstantGrammar = 'an RFC 3339 UTC instant ending in Z';

/// The C0 wire grammar for a duration.
const String wireDurationGrammar = 'an ISO 8601 duration';

/// The C0 wire grammar for a timezone identifier.
const String wireTimezoneGrammar = 'an IANA timezone identifier';

/// A C0 `YYYY-MM-DD` calendar date.
///
/// The value is validated on construction, so an existing instance is always a
/// real calendar date — `2026-02-30` cannot be represented.
final class WireDate {
  const WireDate._(this.year, this.month, this.day);

  /// Builds a date from its components.
  static Result<WireDate> of(int year, int month, int day) =>
      _build(year, month, day, '$year-$month-$day', 'WireDate.of');

  /// Parses the canonical `YYYY-MM-DD` wire form.
  static Result<WireDate> parse(String value) {
    final RegExpMatch? match = _datePattern.firstMatch(value);
    if (match == null) {
      return invalidWireFormat<WireDate>(
        operation: 'WireDate.parse',
        expected: wireDateGrammar,
        value: value,
      );
    }
    // The ORIGINAL wire string is carried into validation so a component
    // failure reports what the caller actually passed, not a re-rendering of it.
    return _build(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      value,
      'WireDate.parse',
    );
  }

  static Result<WireDate> _build(
    int year,
    int month,
    int day,
    String source,
    String operation,
  ) => _validateDate(
    year,
    month,
    day,
    source,
    operation,
  ).map((void _) => WireDate._(year, month, day));

  /// Four-digit year, `1` through `9999`.
  final int year;

  /// Month of year, `1` through `12`.
  final int month;

  /// Day of month, valid for [year] and [month].
  final int day;

  @override
  String toString() => '${_pad(year, 4)}-${_pad(month, 2)}-${_pad(day, 2)}';

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

  /// Builds a time from its components.
  static Result<WireTime> of(int hour, int minute, int second) =>
      _build(hour, minute, second, '$hour:$minute:$second', 'WireTime.of');

  /// Parses the canonical `HH:mm:ss` wire form.
  static Result<WireTime> parse(String value) {
    final RegExpMatch? match = _timePattern.firstMatch(value);
    if (match == null) {
      return invalidWireFormat<WireTime>(
        operation: 'WireTime.parse',
        expected: wireTimeGrammar,
        value: value,
      );
    }
    return _build(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      value,
      'WireTime.parse',
    );
  }

  static Result<WireTime> _build(
    int hour,
    int minute,
    int second,
    String source,
    String operation,
  ) => _validateTime(
    hour,
    minute,
    second,
    source,
    operation,
  ).map((void _) => WireTime._(hour, minute, second));

  /// Hour of day, `0` through `23`.
  final int hour;

  /// Minute of hour, `0` through `59`.
  final int minute;

  /// Second of minute, `0` through `59`. C0 carries no leap second.
  final int second;

  @override
  String toString() => '${_pad(hour, 2)}:${_pad(minute, 2)}:${_pad(second, 2)}';

  @override
  bool operator ==(Object other) =>
      other is WireTime &&
      other.hour == hour &&
      other.minute == minute &&
      other.second == second;

  @override
  int get hashCode => Object.hash(hour, minute, second);
}

/// A validated ISO 8601 duration, preserved without lossy conversion.
///
/// C0 carries durations as ISO 8601 strings precisely because calendar units
/// (`Y`, `M`, `W`) have no fixed length; converting to a Dart [Duration] would
/// have to invent one. The original designation is kept verbatim except that a
/// decimal comma is normalised to a decimal point, which ISO 8601 permits and
/// every reader accepts.
final class IsoDuration {
  const IsoDuration._(this.value);

  /// Parses an ISO 8601 duration designation.
  static Result<IsoDuration> parse(String value) {
    if (!_durationPattern.hasMatch(value)) {
      return invalidWireFormat<IsoDuration>(
        operation: 'IsoDuration.parse',
        expected: wireDurationGrammar,
        value: value,
      );
    }
    return Ok<IsoDuration>(IsoDuration._(value.replaceAll(',', '.')));
  }

  /// The normalised designation.
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
/// bundled as [ianaTimeZoneRelease], not a lexical shape check, so the answer
/// does not depend on host `/usr/share/zoneinfo` data. Canonical zones
/// (`Asia/Singapore`), IANA aliases (`US/Eastern`), the `Etc/*` family, legacy
/// IANA-defined short ids (`EST`, `GMT`), and bare `UTC` are accepted; offsets
/// (`+08:00`), non-IANA abbreviations (`PST`), wrong case, and path-traversal
/// components (`Area/../Location`) are rejected.
final class IanaTimezone {
  const IanaTimezone._(this.value);

  /// Parses an IANA timezone identifier.
  static Result<IanaTimezone> parse(String value) {
    if (!isIanaTimeZone(value)) {
      return invalidWireFormat<IanaTimezone>(
        operation: 'IanaTimezone.parse',
        expected: wireTimezoneGrammar,
        value: value,
      );
    }
    return Ok<IanaTimezone>(IanaTimezone._(value));
  }

  /// The identifier, exactly as the IANA release spells it.
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
///
/// The instant is converted to UTC first, so a local-zone [DateTime] is
/// normalised rather than rejected. A year outside `1..9999` has no RFC 3339
/// representation and is reported as an `invalid_format` [Problem].
Result<String> formatRfc3339Utc(DateTime value) {
  final DateTime utc = value.toUtc();
  return _validateDate(
    utc.year,
    utc.month,
    utc.day,
    utc.toIso8601String(),
    'formatRfc3339Utc',
  ).map((void _) => utc.toIso8601String());
}

/// Parses a STRICT RFC 3339 UTC instant.
///
/// Only the `Z` designator is accepted. A numeric offset — even `+00:00` — is
/// rejected on purpose: C0 §1 fixes ONE canonical instant spelling so two
/// services can compare wire bytes, and accepting equivalent spellings would
/// reintroduce the bespoke-format drift this surface exists to kill. Use
/// [normalizeRfc3339ToUtc] when the input legitimately carries an offset.
Result<DateTime> parseRfc3339Utc(String value) {
  final RegExpMatch? match = _instantPattern.firstMatch(value);
  if (match == null) {
    return invalidWireFormat<DateTime>(
      operation: 'parseRfc3339Utc',
      expected: wireInstantGrammar,
      value: value,
    );
  }
  final Result<void> date = _validateDate(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    value,
    'parseRfc3339Utc',
  );
  if (date case Err<void>(problem: final Problem problem)) {
    return Err<DateTime>(problem);
  }
  final Result<void> time = _validateTime(
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
    value,
    'parseRfc3339Utc',
  );
  if (time case Err<void>(problem: final Problem problem)) {
    return Err<DateTime>(problem);
  }
  return Ok<DateTime>(DateTime.parse(value).toUtc());
}

/// Normalises any RFC 3339 instant — including one carrying a numeric offset —
/// into the canonical UTC `Z` wire form.
///
/// This is the ingress helper for data minted by a system that spells instants
/// with an offset: it accepts the wider grammar once, at the boundary, and hands
/// back bytes [parseRfc3339Utc] will accept forever after.
Result<String> normalizeRfc3339ToUtc(String value) {
  final DateTime? parsed = DateTime.tryParse(value);
  if (parsed == null || !_hasExplicitZoneDesignator(value)) {
    return invalidWireFormat<String>(
      operation: 'normalizeRfc3339ToUtc',
      expected: 'an RFC 3339 instant with a Z or numeric offset designator',
      value: value,
    );
  }
  return formatRfc3339Utc(parsed);
}

/// Codec facade for every C0 temporal wire form.
///
/// Exists so a consumer can inject ONE object and get the whole temporal
/// vocabulary, instead of importing eight free functions. Every member delegates
/// to the surface documented above and returns the same `Result`.
final class WireCodec {
  /// Creates the stateless codec.
  const WireCodec();

  /// Encodes a calendar date.
  String encodeDate(WireDate value) => value.toString();

  /// Decodes a calendar date.
  Result<WireDate> decodeDate(String value) => WireDate.parse(value);

  /// Encodes a wall-clock time.
  String encodeTime(WireTime value) => value.toString();

  /// Decodes a wall-clock time.
  Result<WireTime> decodeTime(String value) => WireTime.parse(value);

  /// Encodes an instant as canonical RFC 3339 UTC.
  Result<String> encodeInstant(DateTime value) => formatRfc3339Utc(value);

  /// Decodes a strict RFC 3339 UTC instant.
  Result<DateTime> decodeInstant(String value) => parseRfc3339Utc(value);

  /// Normalises an offset-carrying instant into the canonical UTC form.
  Result<String> normalizeInstant(String value) => normalizeRfc3339ToUtc(value);

  /// Encodes a duration.
  String encodeDuration(IsoDuration value) => value.toString();

  /// Decodes a duration.
  Result<IsoDuration> decodeDuration(String value) => IsoDuration.parse(value);

  /// Encodes a timezone identifier.
  String encodeTimezone(IanaTimezone value) => value.toString();

  /// Decodes a timezone identifier.
  Result<IanaTimezone> decodeTimezone(String value) =>
      IanaTimezone.parse(value);
}

bool _hasExplicitZoneDesignator(String value) =>
    value.endsWith('Z') ||
    value.endsWith('z') ||
    RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(value);

Result<void> _validateDate(
  int year,
  int month,
  int day,
  String source,
  String operation,
) {
  if (year < 1 || year > 9999) {
    return invalidWireFormat<void>(
      operation: operation,
      expected: wireDateGrammar,
      value: source,
    );
  }
  final DateTime date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    return invalidWireFormat<void>(
      operation: operation,
      expected: wireDateGrammar,
      value: source,
    );
  }
  return const Ok<void>(null);
}

Result<void> _validateTime(
  int hour,
  int minute,
  int second,
  String source,
  String operation,
) {
  if (hour < 0 ||
      hour > 23 ||
      minute < 0 ||
      minute > 59 ||
      second < 0 ||
      second > 59) {
    return invalidWireFormat<void>(
      operation: operation,
      expected: wireTimeGrammar,
      value: source,
    );
  }
  return const Ok<void>(null);
}

String _pad(int value, int width) => value.toString().padLeft(width, '0');
