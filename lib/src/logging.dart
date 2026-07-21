import 'dart:collection';

import 'package:diene_result/diene_result.dart';

enum LogLevel { trace, debug, info, warning, error, fatal }

/// One structured log emission.
final class LogRecord {
  LogRecord({
    required this.timestamp,
    required this.level,
    required this.message,
    Map<String, Object?> attributes = const <String, Object?>{},
    this.error,
    this.stackTrace,
  }) : attributes = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(attributes),
       );

  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final Map<String, Object?> attributes;
  final String? error;
  final String? stackTrace;
}

/// Receives structured application logs.
///
/// Dart does not ship an OTel implementation of this seam. Flutter adapters
/// route records through the frontend Faro path.
abstract interface class LoggerSink {
  Result<void> emit(LogRecord record);
}
