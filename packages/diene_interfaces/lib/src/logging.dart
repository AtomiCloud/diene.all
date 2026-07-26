/// The structured-log emit seam.
library;

import 'dart:collection';

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';
import 'telemetry.dart';

/// Severity of a log record.
enum LogLevel {
  /// Fine-grained diagnostic detail.
  trace,

  /// Developer-facing diagnostic detail.
  debug,

  /// Normal operational events.
  info,

  /// Recoverable anomalies.
  warning,

  /// Failures a caller should act on.
  error,

  /// Failures that end the process or session.
  fatal,
}

/// One structured log emission.
final class LogRecord {
  /// Creates a log record.
  ///
  /// [attributes] is copied and exposed unmodifiable so an emitted record
  /// cannot be mutated after the fact.
  LogRecord({
    required this.timestamp,
    required this.level,
    required this.message,
    TelemetryAttributes attributes = const <String, Object?>{},
    this.error,
    this.stackTrace,
  }) : attributes = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(attributes),
       );

  /// When the event happened.
  final DateTime timestamp;

  /// Severity of the event.
  final LogLevel level;

  /// Human-readable message.
  final String message;

  /// Structured attributes attached to the event.
  final TelemetryAttributes attributes;

  /// Rendered error, when the event describes a failure.
  final String? error;

  /// Rendered stack trace, when one was captured.
  final String? stackTrace;

  @override
  String toString() => 'LogRecord(${level.name}, $message)';
}

/// Receives structured application logs.
///
/// Dart ships no OTel implementation of this seam. Flutter adapters route
/// records through the frontend Faro path (RB-19); this library owns the seam
/// and its in-memory fake, never an exporter.
abstract interface class LoggerSink {
  /// Emits one record.
  Result<void> emit(LogRecord record);

  /// Flushes any buffered records.
  Future<Result<void>> flush();
}

/// Validates a record before an implementation emits it.
Result<LogRecord> checkLogRecord(
  LogRecord record, {
  String operation = 'emit',
}) {
  if (record.message.trim().isEmpty) {
    return invalidInput<LogRecord>(
      port: PortName.logging,
      operation: operation,
      field: 'message',
      message: 'Log message must be non-blank',
    );
  }
  if (!record.timestamp.isUtc) {
    return invalidInput<LogRecord>(
      port: PortName.logging,
      operation: operation,
      field: 'timestamp',
      message: 'Log timestamp must be UTC',
    );
  }
  return checkTelemetryAttributes(
    record.attributes,
    port: PortName.logging,
    operation: operation,
  ).map((TelemetryAttributes _) => record);
}
