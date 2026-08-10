import 'package:diene_interfaces/diene_interfaces.dart';
import 'package:diene_interfaces/test_helper.dart';
import 'package:diene_result/diene_result.dart';

/// A component that depends on the narrow seams it actually needs, not on
/// `dart:io`. Every fallible call is handled as a `Result` — no try/catch.
Future<Result<String>> describeConfig(Vfs vfs, System system) async {
  final Result<String> path = system
      .environment('CONFIG_PATH')
      .andThen(
        (String? value) => value == null
            ? invalidInput<String>(
                port: PortName.system,
                operation: 'environment',
                field: 'CONFIG_PATH',
                message: 'CONFIG_PATH is not set',
              )
            : Ok<String>(value),
      );
  return switch (path) {
    Err<String>() => path,
    Ok<String>(:final String value) => await vfs.readText(value),
  };
}

/// Demonstrates the clean consumer path using the shipped in-memory fakes.
Future<void> main() async {
  final InMemorySystem system = InMemorySystem(
    environment: <String, String>{'CONFIG_PATH': '/etc/app.yaml'},
  );
  final InMemoryVfs vfs = InMemoryVfs(
    files: <String, List<int>>{'/etc/app.yaml': 'landscape: lapras'.codeUnits},
  );

  final Result<String> found = await describeConfig(vfs, system);
  assert(found.unwrap() == 'landscape: lapras', 'the seam reads the file');

  // The failure path is a value, so there is nothing to catch.
  final Result<String> missing = await describeConfig(
    InMemoryVfs(),
    InMemorySystem(),
  );
  assert(missing.isErr, 'an unset variable is reported as a Problem');

  // Telemetry emits through the same Result discipline.
  final InMemoryLoggerSink logger = InMemoryLoggerSink();
  final Result<void> emitted = logger.emit(
    LogRecord(
      timestamp: system.nowUtc().unwrap(),
      level: LogLevel.info,
      message: 'config loaded',
      attributes: <String, Object?>{'path': '/etc/app.yaml'},
    ),
  );
  assert(emitted.isOk, 'the fake accepted the record');
  assert(logger.records.length == 1, 'the fake captured the record');
}
