/// JSON-compatible C0 Result wire form: `['ok', value]` or `['err', problem]`.
typedef ResultSerial = List<Object?>;

/// JSON-compatible C0 Option wire form: `['some', value]` or `['none', null]`.
typedef OptionSerial = List<Object?>;

/// Validates and reads a two-item tagged wire value.
(String, Object?) readTaggedWire(
  List<Object?> serial, {
  required String monad,
  required Set<String> tags,
}) {
  if (serial.length != 2) {
    throw FormatException('$monad wire value must contain exactly two items.');
  }

  final Object? rawTag = serial.first;
  if (rawTag is! String || !tags.contains(rawTag)) {
    throw FormatException('$monad wire value has an unknown tag: $rawTag.');
  }

  return (rawTag, serial[1]);
}

/// Creates an immutable tagged wire value.
List<Object?> taggedWire(String tag, Object? value) =>
    List<Object?>.unmodifiable(<Object?>[tag, value]);
