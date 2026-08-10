/// Shared attribute rules for the logging and metrics emit seams.
///
/// Both telemetry seams carry the same attribute bag, so the validation lives
/// here once instead of twice. Dart/Flutter telemetry rides Faro at runtime —
/// this library ships no exporter and no OTel implementer (RB-19).
library;

import 'dart:collection';

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';

/// A validated telemetry attribute bag.
///
/// Values are restricted to finite primitives so any downstream transport
/// (Faro, a log formatter, a metrics registry) can render them without
/// negotiating a schema.
typedef TelemetryAttributes = Map<String, Object?>;

/// The empty, unmodifiable attribute bag.
final TelemetryAttributes emptyTelemetryAttributes =
    UnmodifiableMapView<String, Object?>(const <String, Object?>{});

/// Validates and canonicalises a telemetry attribute bag.
///
/// Accepts a `null` bag as the empty bag. Rejects blank or NUL-bearing keys and
/// any value that is not a finite `num`, `bool`, or `String`. On success the
/// returned map is key-sorted and unmodifiable, so two equal bags always render
/// identically.
Result<TelemetryAttributes> checkTelemetryAttributes(
  TelemetryAttributes? attributes, {
  required PortName port,
  required String operation,
}) {
  if (attributes == null || attributes.isEmpty) {
    return Ok<TelemetryAttributes>(emptyTelemetryAttributes);
  }
  for (final MapEntry<String, Object?> entry in attributes.entries) {
    if (entry.key.trim().isEmpty || entry.key.codeUnits.contains(0)) {
      return invalidInput<TelemetryAttributes>(
        port: port,
        operation: operation,
        field: 'attributes',
        message: 'Telemetry attribute names must be non-blank and NUL-free',
      );
    }
    final Object? value = entry.value;
    final bool finitePrimitive =
        value is bool || value is String || (value is num && value.isFinite);
    if (!finitePrimitive) {
      return invalidInput<TelemetryAttributes>(
        port: port,
        operation: operation,
        field: 'attributes.${entry.key}',
        message: 'Telemetry attribute values must be finite primitives',
      );
    }
  }
  final List<String> keys = attributes.keys.toList()..sort();
  return Ok<TelemetryAttributes>(
    UnmodifiableMapView<String, Object?>(<String, Object?>{
      for (final String key in keys) key: attributes[key],
    }),
  );
}
