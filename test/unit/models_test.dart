import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:test/test.dart';

void main() {
  group('value contracts', () {
    test('TerminalCommand snapshots mutable inputs', () {
      // Arrange.
      final List<String> arguments = <String>['first'];
      final Map<String, String> environment = <String, String>{'A': '1'};

      // Act.
      final TerminalCommand command = TerminalCommand(
        executable: 'tool',
        arguments: arguments,
        workingDirectory: '/work',
        environment: environment,
        includeParentEnvironment: false,
        runInShell: true,
      );
      arguments.add('second');
      environment['B'] = '2';

      // Assert.
      expect(command.executable, 'tool');
      expect(command.arguments, <String>['first']);
      expect(command.workingDirectory, '/work');
      expect(command.environment, <String, String>{'A': '1'});
      expect(command.includeParentEnvironment, isFalse);
      expect(command.runInShell, isTrue);
      expect(() => command.arguments.add('third'), throwsUnsupportedError);
    });

    test('TerminalOutput classifies child exit status', () {
      // Arrange.
      const TerminalOutput successful = TerminalOutput(
        exitCode: 0,
        stdout: 'ok',
        stderr: '',
      );
      const TerminalOutput unsuccessful = TerminalOutput(
        exitCode: 3,
        stdout: '',
        stderr: 'bad',
      );

      // Act and assert.
      expect(successful.succeeded, isTrue);
      expect(unsuccessful.succeeded, isFalse);
      expect(unsuccessful.exitCode, 3);
      expect(unsuccessful.stderr, 'bad');
    });

    test('LogRecord snapshots attributes and preserves error context', () {
      // Arrange.
      final Map<String, Object?> attributes = <String, Object?>{'request': 7};
      final DateTime timestamp = DateTime.utc(2026, 7, 21);

      // Act.
      final LogRecord record = LogRecord(
        timestamp: timestamp,
        level: LogLevel.error,
        message: 'failed',
        attributes: attributes,
        error: 'problem',
        stackTrace: 'trace',
      );
      attributes['request'] = 8;

      // Assert.
      expect(record.timestamp, timestamp);
      expect(record.level, LogLevel.error);
      expect(record.message, 'failed');
      expect(record.attributes, <String, Object?>{'request': 7});
      expect(record.error, 'problem');
      expect(record.stackTrace, 'trace');
      expect(LogLevel.values, hasLength(6));
    });

    test('MetricRecord snapshots attributes and preserves sample metadata', () {
      // Arrange.
      final Map<String, Object?> attributes = <String, Object?>{'route': '/'};
      final DateTime timestamp = DateTime.utc(2026, 7, 21);

      // Act.
      final MetricRecord record = MetricRecord(
        timestamp: timestamp,
        name: 'requests',
        kind: MetricKind.counter,
        value: 2,
        unit: 'request',
        attributes: attributes,
      );
      attributes['route'] = '/changed';

      // Assert.
      expect(record.timestamp, timestamp);
      expect(record.name, 'requests');
      expect(record.kind, MetricKind.counter);
      expect(record.value, 2);
      expect(record.unit, 'request');
      expect(record.attributes, <String, Object?>{'route': '/'});
      expect(MetricKind.values, <MetricKind>[
        MetricKind.counter,
        MetricKind.gauge,
        MetricKind.histogram,
      ]);
    });

    test('VfsEntry preserves portable metadata', () {
      // Arrange and act.
      final DateTime modified = DateTime.utc(2026, 7, 21);
      final VfsEntry entry = VfsEntry(
        path: '/notes.txt',
        type: VfsEntryType.file,
        size: 12,
        modifiedAt: modified,
      );

      // Assert.
      expect(entry.path, '/notes.txt');
      expect(entry.type, VfsEntryType.file);
      expect(entry.size, 12);
      expect(entry.modifiedAt, modified);
      expect(VfsEntryType.values, hasLength(3));
    });
  });
}
