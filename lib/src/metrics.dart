import 'dart:collection';

import 'package:diene_result/diene_result.dart';

enum MetricKind { counter, gauge, histogram }

/// One metric sample emitted by an application.
final class MetricRecord {
  MetricRecord({
    required this.timestamp,
    required this.name,
    required this.kind,
    required this.value,
    this.unit,
    Map<String, Object?> attributes = const <String, Object?>{},
  }) : attributes = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(attributes),
       );

  final DateTime timestamp;
  final String name;
  final MetricKind kind;
  final num value;
  final String? unit;
  final Map<String, Object?> attributes;
}

/// Receives application metric samples.
///
/// Dart does not ship an OTel implementation of this seam. Flutter adapters
/// route samples through the frontend Faro path.
abstract interface class MetricsCollector {
  Result<void> emit(MetricRecord record);
}
