import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support/result_expectations.dart';

void main() {
  group('telemetry fakes', () {
    test('logger records successful emissions', () {
      // Arrange.
      final InMemoryLoggerSink sink = InMemoryLoggerSink();
      final LogRecord record = LogRecord(
        timestamp: DateTime.utc(2026),
        level: LogLevel.info,
        message: 'ready',
      );

      // Act.
      final Result<void> result = sink.emit(record);

      // Assert.
      expectSuccess(result);
      expect(sink.records, <LogRecord>[record]);
    });

    test('logger proves failure injection does not record', () {
      // Arrange.
      final Err<void> injected = failure<void>('log');
      final InMemoryLoggerSink sink = InMemoryLoggerSink()..enqueue(injected);
      final LogRecord record = LogRecord(
        timestamp: DateTime.utc(2026),
        level: LogLevel.error,
        message: 'failed',
      );

      // Act.
      final Result<void> result = sink.emit(record);

      // Assert.
      expect(result, same(injected));
      expect(sink.records, isEmpty);
    });

    test('metrics collector records successful emissions', () {
      // Arrange.
      final InMemoryMetricsCollector collector = InMemoryMetricsCollector();
      final MetricRecord record = MetricRecord(
        timestamp: DateTime.utc(2026),
        name: 'latency',
        kind: MetricKind.histogram,
        value: 12.5,
      );

      // Act.
      final Result<void> result = collector.emit(record);

      // Assert.
      expectSuccess(result);
      expect(collector.records, <MetricRecord>[record]);
    });

    test('metrics proves failure injection does not record', () {
      // Arrange.
      final Err<void> injected = failure<void>('metric');
      final InMemoryMetricsCollector collector = InMemoryMetricsCollector()
        ..enqueue(injected);
      final MetricRecord record = MetricRecord(
        timestamp: DateTime.utc(2026),
        name: 'attempts',
        kind: MetricKind.counter,
        value: 1,
      );

      // Act.
      final Result<void> result = collector.emit(record);

      // Assert.
      expect(result, same(injected));
      expect(collector.records, isEmpty);
    });
  });
}
