import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/test_helper.dart';
import 'package:test/test.dart';

void main() {
  group('LogRecord', () {
    test('copies and freezes its attributes', () {
      // Arrange.
      final Map<String, Object?> attributes = <String, Object?>{'route': '/a'};

      // Act.
      final LogRecord record = LogRecord(
        timestamp: DateTime.utc(2026, 7, 25, 6),
        level: LogLevel.error,
        message: 'request failed',
        attributes: attributes,
        error: 'SocketException',
        stackTrace: '#0 main',
      );
      attributes['injected'] = true;

      // Assert.
      expect(record.attributes, <String, Object?>{'route': '/a'});
      expect(() => record.attributes['x'] = 1, throwsUnsupportedError);
      expect(record.error, 'SocketException');
      expect(record.stackTrace, '#0 main');
      expect(record.toString(), 'LogRecord(error, request failed)');
    });

    test('defaults to no attributes, error, or stack trace', () {
      // Arrange & Act.
      final LogRecord record = LogRecord(
        timestamp: DateTime.utc(2026),
        level: LogLevel.trace,
        message: 'tick',
      );

      // Assert.
      expect(record.attributes, isEmpty);
      expect(record.error, isNull);
      expect(record.stackTrace, isNull);
      expect(LogLevel.values, hasLength(6));
    });
  });

  group('checkLogRecord', () {
    test('accepts a UTC record with valid attributes', () {
      // Arrange.
      final LogRecord record = LogRecord(
        timestamp: DateTime.utc(2026),
        level: LogLevel.info,
        message: 'ready',
        attributes: <String, Object?>{'attempt': 1},
      );

      // Act & Assert.
      expect(expectOk(checkLogRecord(record)), same(record));
    });

    test('rejects a blank message', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkLogRecord(
          LogRecord(
            timestamp: DateTime.utc(2026),
            level: LogLevel.debug,
            message: '   ',
          ),
        ),
      );

      // Assert.
      expect(problem.data['field'], 'message');
      expect(problem.data['port'], 'logging');
    });

    test('rejects a non-UTC timestamp', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkLogRecord(
          LogRecord(
            timestamp: DateTime(2026, 7, 25),
            level: LogLevel.fatal,
            message: 'crash',
          ),
        ),
      );

      // Assert.
      expect(problem.data['field'], 'timestamp');
    });

    test('rejects invalid attributes through the shared telemetry rule', () {
      // Arrange & Act.
      final Problem problem = expectErr(
        checkLogRecord(
          LogRecord(
            timestamp: DateTime.utc(2026),
            level: LogLevel.warning,
            message: 'odd',
            attributes: <String, Object?>{
              'nested': <int>[1],
            },
          ),
        ),
      );

      // Assert.
      expect(problem.data['field'], 'attributes.nested');
      expect(problem.data['port'], 'logging');
    });
  });
}
