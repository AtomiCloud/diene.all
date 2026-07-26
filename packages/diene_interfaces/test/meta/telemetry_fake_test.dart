import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

LogRecord _log([LogLevel level = LogLevel.info]) => LogRecord(
  timestamp: DateTime.utc(2026, 7, 25),
  level: level,
  message: 'event',
);

MetricRecord _metric([num value = 1]) => MetricRecord(
  timestamp: DateTime.utc(2026, 7, 25),
  name: 'requests.total',
  kind: MetricKind.counter,
  value: value,
);

void main() {
  group('InMemoryLoggerSink', () {
    test('captures emitted records in call order', () {
      // Arrange.
      final InMemoryLoggerSink sink = InMemoryLoggerSink();

      // Act.
      expectOk(sink.emit(_log()));
      expectOk(sink.emit(_log(LogLevel.error)));

      // Assert.
      expect(sink.records.map((LogRecord record) => record.level), <LogLevel>[
        LogLevel.info,
        LogLevel.error,
      ]);
    });

    test('a scripted failure crosses as a value and is not captured', () {
      // Arrange.
      final InMemoryLoggerSink sink = InMemoryLoggerSink()
        ..enqueue(
          portFailure<void>(
            port: PortName.logging,
            code: PortErrorCode.io,
            operation: 'emit',
            message: 'Sink write failed',
          ),
        );

      // Act.
      expectPortProblem(
        expectErr(sink.emit(_log())),
        port: PortName.logging,
        code: PortErrorCode.io,
      );

      // Assert.
      expect(sink.records, isEmpty, reason: 'a rejected record is not stored');
      expectOk(sink.emit(_log()));
      expect(sink.records, hasLength(1));
    });

    test('counts flushes and honours a scripted flush failure', () async {
      // Arrange.
      final InMemoryLoggerSink sink = InMemoryLoggerSink()
        ..enqueueFlushResult(
          portFailure<void>(
            port: PortName.logging,
            code: PortErrorCode.unavailable,
            operation: 'flush',
            message: 'Sink unavailable',
          ),
        );

      // Act.
      expectPortProblem(
        expectErr(await sink.flush()),
        port: PortName.logging,
        code: PortErrorCode.unavailable,
      );
      expectOk(await sink.flush());

      // Assert.
      expect(sink.flushCount, 2);
    });
  });

  group('InMemoryMetricsCollector', () {
    test('captures emitted samples in call order', () {
      // Arrange.
      final InMemoryMetricsCollector collector = InMemoryMetricsCollector();

      // Act.
      expectOk(collector.emit(_metric()));
      expectOk(collector.emit(_metric(4)));

      // Assert.
      expect(
        collector.records.map((MetricRecord record) => record.value),
        <num>[1, 4],
      );
    });

    test('a scripted failure crosses as a value and is not captured', () {
      // Arrange.
      final InMemoryMetricsCollector collector = InMemoryMetricsCollector()
        ..enqueue(
          portFailure<void>(
            port: PortName.metrics,
            code: PortErrorCode.io,
            operation: 'emit',
            message: 'Registry write failed',
          ),
        );

      // Act.
      expectPortProblem(
        expectErr(collector.emit(_metric())),
        port: PortName.metrics,
        code: PortErrorCode.io,
      );

      // Assert.
      expect(collector.records, isEmpty);
      expectOk(collector.emit(_metric()));
      expect(collector.records, hasLength(1));
    });

    test('counts flushes and honours a scripted flush failure', () async {
      // Arrange.
      final InMemoryMetricsCollector collector = InMemoryMetricsCollector()
        ..enqueueFlushResult(
          portFailure<void>(
            port: PortName.metrics,
            code: PortErrorCode.timeout,
            operation: 'flush',
            message: 'Flush timed out',
          ),
        );

      // Act.
      expectPortProblem(
        expectErr(await collector.flush()),
        port: PortName.metrics,
        code: PortErrorCode.timeout,
      );
      expectOk(await collector.flush());

      // Assert.
      expect(collector.flushCount, 2);
    });
  });
}
