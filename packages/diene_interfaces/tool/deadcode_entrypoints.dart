// Production dead-code root for the published diene_interfaces surface.
//
// This is tooling, not a test. dart_code_linter otherwise treats only the
// public barrel (diene_interfaces.dart) as an entrypoint and incorrectly
// reports the test_helper.dart public members as unused. Referencing every
// public export here keeps the production-only dead-code pass honest without
// any exclusion list. deadcode.sh copies this file to bin/main.dart inside the
// production-only sandbox, so it lives in the member package where
// `package:diene_interfaces` resolves cleanly (and is excluded from the
// published archive by .pubignore).
import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

Future<void> main() async {
  // The seam vocabulary and the ONE type-URI builder.
  final Problem problem = portProblem(
    port: PortName.vfs,
    code: PortErrorCode.notFound,
    operation: 'readText',
    message: 'Path not found',
    portal: ErrorPortal.localError,
  );
  final Err<int> failure = portFailure<int>(
    port: PortName.system,
    code: PortErrorCode.io,
    operation: 'nowUtc',
    message: 'Clock unavailable',
  );
  final Err<int> rejected = invalidInput<int>(
    port: PortName.terminal,
    operation: 'run',
    field: 'executable',
    message: 'Executable must be non-blank',
  );
  if (problem.status != 404 || failure.problem.status != 500) {
    throw StateError('unexpected seam problem status');
  }
  if (rejected.problem.status != 400 || interfacesProblemVersion.isEmpty) {
    throw StateError('unexpected invalid-input status');
  }

  // Every seam validator.
  final System system = InMemorySystem();
  final Vfs vfs = InMemoryVfs();
  final Terminal terminal = InMemoryTerminal(input: <String>['line']);
  final LoggerSink logger = InMemoryLoggerSink();
  final MetricsCollector metrics = InMemoryMetricsCollector();

  final LogRecord log = LogRecord(
    timestamp: system.nowUtc().unwrap(),
    level: LogLevel.info,
    message: 'dead-code entrypoint',
    attributes: <String, Object?>{'phase': 'deadcode'},
    error: null,
    stackTrace: null,
  );
  final MetricRecord metric = MetricRecord(
    timestamp: system.nowUtc().unwrap(),
    name: 'deadcode.total',
    kind: MetricKind.counter,
    value: 1,
    unit: 'calls',
  );
  final TerminalCommand command = TerminalCommand(
    executable: 'true',
    arguments: const <String>['--version'],
    workingDirectory: '/',
    environment: const <String, String>{'LC_ALL': 'C'},
    includeParentEnvironment: false,
    runInShell: false,
  );
  const TerminalOutput output = TerminalOutput(
    exitCode: 0,
    stdout: '',
    stderr: '',
  );
  const TerminalWrite write = TerminalWrite(
    channel: TerminalChannel.stdout,
    text: 'hello',
    newline: true,
  );
  const TerminalRead read = TerminalRead(prompt: 'name? ');

  checkLogRecord(log).unwrap();
  checkMetricRecord(metric).unwrap();
  checkTerminalCommand(command).unwrap();
  checkTerminalOutput(output).unwrap();
  checkTerminalWrite(write).unwrap();
  checkTerminalRead(read).unwrap();
  checkVfsPath('/etc/hosts').unwrap();
  checkTelemetryAttributes(
    log.attributes,
    port: PortName.logging,
    operation: 'emit',
  ).unwrap();
  if (emptyTelemetryAttributes.isNotEmpty ||
      !metricNamePattern.hasMatch(metric.name)) {
    throw StateError('unexpected telemetry constants');
  }

  // Every seam member, through the shipped fakes.
  system.environment('HOME').unwrap();
  system.currentDirectory().unwrap();
  (await system.delay(Duration.zero)).unwrap();
  (await vfs.writeBytes('/a.bin', const <int>[
    1,
  ], createParents: true)).unwrap();
  (await vfs.writeText('/a.txt', 'text', createParents: true)).unwrap();
  (await vfs.exists('/a.txt')).unwrap();
  (await vfs.readBytes('/a.bin')).unwrap();
  (await vfs.readText('/a.txt')).unwrap();
  final VfsStat stat = (await vfs.stat('/a.txt')).unwrap();
  final List<VfsEntry> entries = (await vfs.list(
    '/',
    recursive: true,
  )).unwrap();
  (await vfs.createDirectory('/dir', recursive: true)).unwrap();
  (await vfs.delete('/dir', recursive: true)).unwrap();
  if (stat.type != VfsEntryType.file ||
      entries.isEmpty ||
      entries.first.size < 0 ||
      entries.first.path.isEmpty ||
      entries.first.type == VfsEntryType.link ||
      entries.first.modifiedAt == null ||
      stat.size < 0 ||
      stat.modifiedAt == null) {
    throw StateError('unexpected filesystem metadata');
  }

  (await terminal.write(write)).unwrap();
  (await terminal.readLine(read)).unwrap();
  (await terminal.readLine()).unwrap();
  if (!terminal.interactive || !output.succeeded || command.runInShell) {
    throw StateError('unexpected terminal state');
  }
  logger.emit(log).unwrap();
  (await logger.flush()).unwrap();
  metrics.emit(metric).unwrap();
  (await metrics.flush()).unwrap();

  // The fakes' scripting and assertion surface.
  final InMemorySystem scriptedSystem =
      InMemorySystem(
          environment: const <String, String>{'A': 'b'},
          directory: '/',
          now: DateTime.utc(2026),
        )
        ..enqueueEnvironmentResult(const Ok<String?>('x'))
        ..enqueueDirectoryResult(const Ok<String>('/'))
        ..enqueueClockResult(Ok<DateTime>(DateTime.utc(2026)))
        ..enqueueDelayResult(const Ok<void>(null));
  scriptedSystem.environmentVariables['C'] = 'd';
  scriptedSystem.directory = '/';
  scriptedSystem.now = DateTime.utc(2026);
  if (scriptedSystem.requestedDelays.isNotEmpty) {
    throw StateError('unexpected delay log');
  }

  final InMemoryVfs scriptedVfs =
      InMemoryVfs(
          files: <String, List<int>>{
            '/seed.txt': const <int>[1],
          },
          directories: const <String>['/'],
          modifiedAt: DateTime.utc(2026),
        )
        ..enqueueExistsResult(const Ok<bool>(true))
        ..enqueueStatResult(
          const Ok<VfsStat>(VfsStat(type: VfsEntryType.file, size: 1)),
        )
        ..enqueueReadBytesResult(const Ok<List<int>>(<int>[1]))
        ..enqueueReadTextResult(const Ok<String>('x'))
        ..enqueueWriteBytesResult(const Ok<void>(null))
        ..enqueueWriteTextResult(const Ok<void>(null))
        ..enqueueListResult(const Ok<List<VfsEntry>>(<VfsEntry>[]))
        ..enqueueCreateDirectoryResult(const Ok<void>(null))
        ..enqueueDeleteResult(const Ok<void>(null));
  if (scriptedVfs.files.isEmpty ||
      scriptedVfs.directories.isEmpty ||
      scriptedVfs.modifiedAt.isBefore(DateTime.utc(2000)) ||
      InMemoryVfs.normalizePath('a').isEmpty) {
    throw StateError('unexpected filesystem snapshot');
  }

  final InMemoryTerminal scriptedTerminal = InMemoryTerminal(interactive: false)
    ..enqueue(const Ok<TerminalOutput>(output))
    ..enqueueWriteResult(const Ok<void>(null))
    ..enqueueReadResult(const Ok<String?>('scripted'));
  (await scriptedTerminal.run(command)).unwrap();
  if (scriptedTerminal.commands.isEmpty ||
      scriptedTerminal.writes.isNotEmpty ||
      scriptedTerminal.reads.isNotEmpty) {
    throw StateError('unexpected terminal transcript');
  }

  final InMemoryLoggerSink scriptedLogger = InMemoryLoggerSink()
    ..enqueue(const Ok<void>(null))
    ..enqueueFlushResult(const Ok<void>(null));
  final InMemoryMetricsCollector scriptedMetrics = InMemoryMetricsCollector()
    ..enqueue(const Ok<void>(null))
    ..enqueueFlushResult(const Ok<void>(null));
  if (scriptedLogger.records.isNotEmpty ||
      scriptedLogger.flushCount != 0 ||
      scriptedMetrics.records.isNotEmpty ||
      scriptedMetrics.flushCount != 0) {
    throw StateError('unexpected telemetry transcript');
  }

  // Accept a known-good envelope through the shipped assertion...
  expectPortProblem(
    problem,
    port: PortName.vfs,
    code: PortErrorCode.notFound,
    operation: 'readText',
  );

  // ...and prove the failure type is reachable by rejecting a known-bad one.
  try {
    expectPortProblem(
      problem,
      port: PortName.system,
      code: PortErrorCode.notFound,
    );
  } on SeamAssertionFailure catch (error) {
    if (error.message.isEmpty || error.toString().isEmpty) {
      throw StateError('empty assertion diagnostic');
    }
  }
}
