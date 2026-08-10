/// The metrics emit seam.
library;

import 'dart:collection';

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';
import 'telemetry.dart';

/// The kind of instrument a sample belongs to.
enum MetricKind {
  /// Monotonically increasing total.
  counter,

  /// Point-in-time value.
  gauge,

  /// Distribution observation.
  histogram,
}

/// Name shape shared with the `lib/bun/interfaces` sibling.
final RegExp metricNamePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_.\-/]{0,254}$');

/// One metric sample emitted by an application.
final class MetricRecord {
  /// Creates a metric sample.
  ///
  /// [attributes] is copied and exposed unmodifiable so an emitted sample
  /// cannot be mutated after the fact.
  MetricRecord({
    required this.timestamp,
    required this.name,
    required this.kind,
    required this.value,
    this.unit,
    TelemetryAttributes attributes = const <String, Object?>{},
  }) : attributes = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(attributes),
       );

  /// When the sample was taken.
  final DateTime timestamp;

  /// Instrument name.
  final String name;

  /// Instrument kind.
  final MetricKind kind;

  /// Observed value.
  final num value;

  /// Unit of measure, when one applies.
  final String? unit;

  /// Structured attributes attached to the sample.
  final TelemetryAttributes attributes;

  @override
  String toString() => 'MetricRecord($name, ${kind.name}, $value)';
}

/// Receives application metric samples.
///
/// Dart ships no OTel implementation of this seam. Flutter adapters route
/// samples through the frontend Faro path (RB-19); this library owns the seam
/// and its in-memory fake, never an exporter.
abstract interface class MetricsCollector {
  /// Emits one sample.
  Result<void> emit(MetricRecord record);

  /// Flushes any buffered samples.
  Future<Result<void>> flush();
}

/// Validates a sample before an implementation emits it.
Result<MetricRecord> checkMetricRecord(
  MetricRecord record, {
  String operation = 'emit',
}) {
  if (!metricNamePattern.hasMatch(record.name)) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'name',
      message: 'Metric name must match $metricNamePattern',
    );
  }
  if (!record.timestamp.isUtc) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'timestamp',
      message: 'Metric timestamp must be UTC',
    );
  }
  if (!record.value.isFinite) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'value',
      message: 'Metric value must be finite',
    );
  }
  if (record.kind == MetricKind.counter && record.value < 0) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'value',
      message: 'Counter samples must not be negative',
    );
  }
  final String? unit = record.unit;
  if (unit != null && unit.trim().isEmpty) {
    return invalidInput<MetricRecord>(
      port: PortName.metrics,
      operation: operation,
      field: 'unit',
      message: 'Unit must be omitted rather than blank',
    );
  }
  return checkTelemetryAttributes(
    record.attributes,
    port: PortName.metrics,
    operation: operation,
  ).map((TelemetryAttributes _) => record);
}
