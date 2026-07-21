import 'dart:convert';
import 'dart:io';

import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';
import 'package:test/test.dart';

import '../support/result_expectations.dart';

void main() {
  test('C0 fixture binds the Dart common-interface boundary', () async {
    // Arrange.
    final String source = await File(
      'test/fixtures/c0/interfaces.json',
    ).readAsString();

    // Act.
    final Map<String, Object?> fixture =
        jsonDecode(source) as Map<String, Object?>;

    // Assert.
    expect(fixture['version'], 1);
    expect((fixture['seams']! as List<Object?>).cast<String>(), <String>[
      'System',
      'Vfs',
      'Terminal',
      'LoggerSink',
      'MetricsCollector',
    ]);
    expect(fixture['fallibleTransport'], 'Result');
    expect(fixture['traceSeamOwned'], isFalse);
    expect(fixture['dartOtelExporter'], isFalse);
    expect(fixture['runtimeTelemetry'], 'Faro');
  });

  test(
    'every fallible seam communicates expected failure through Result',
    () async {
      // Arrange.
      final Failure<String?> systemFailure = failure<String?>('system');
      final Failure<List<int>> vfsFailure = failure<List<int>>('vfs');
      final Failure<TerminalOutput> terminalFailure = failure<TerminalOutput>(
        'terminal',
      );
      final Failure<void> loggingFailure = failure<void>('logging');
      final Failure<void> metricsFailure = failure<void>('metrics');
      final InMemorySystem system = InMemorySystem()
        ..enqueueEnvironmentResult(systemFailure);
      final InMemoryVfs vfs = InMemoryVfs()..enqueueReadBytesResult(vfsFailure);
      final InMemoryTerminal terminal = InMemoryTerminal()
        ..enqueue(terminalFailure);
      final InMemoryLoggerSink logger = InMemoryLoggerSink()
        ..enqueue(loggingFailure);
      final InMemoryMetricsCollector metrics = InMemoryMetricsCollector()
        ..enqueue(metricsFailure);

      // Act.
      final Result<String?> systemResult = system.environment('MISSING');
      final Result<List<int>> vfsResult = await vfs.readBytes('/missing');
      final Result<TerminalOutput> terminalResult = await terminal.run(
        TerminalCommand(executable: 'missing'),
      );
      final Result<void> logResult = logger.emit(
        LogRecord(
          timestamp: DateTime.utc(2026),
          level: LogLevel.warning,
          message: 'warning',
        ),
      );
      final Result<void> metricResult = metrics.emit(
        MetricRecord(
          timestamp: DateTime.utc(2026),
          name: 'attempts',
          kind: MetricKind.counter,
          value: 1,
        ),
      );

      // Assert.
      expect(systemResult, same(systemFailure));
      expect(vfsResult, same(vfsFailure));
      expect(terminalResult, same(terminalFailure));
      expect(logResult, same(loggingFailure));
      expect(metricResult, same(metricsFailure));
    },
  );

  test('terminal non-zero exit remains captured success', () async {
    // Arrange.
    const Success<TerminalOutput> response = Success<TerminalOutput>(
      TerminalOutput(exitCode: 2, stdout: '', stderr: 'usage'),
    );
    final InMemoryTerminal terminal = InMemoryTerminal()..enqueue(response);

    // Act.
    final Result<TerminalOutput> result = await terminal.run(
      TerminalCommand(executable: 'tool'),
    );

    // Assert.
    expect(expectSuccess(result).exitCode, 2);
    expect(expectSuccess(result).succeeded, isFalse);
  });
}
