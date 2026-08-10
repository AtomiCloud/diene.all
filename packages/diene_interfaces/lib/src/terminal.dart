/// The process-execution and interactive-stdio boundary.
library;

import 'dart:collection';

import 'package:diene_result/diene_result.dart';

import 'port_problem.dart';

/// One process invocation requested through the terminal seam.
final class TerminalCommand {
  /// Creates an invocation description.
  ///
  /// [arguments] and [environment] are copied and exposed unmodifiable, so a
  /// caller cannot mutate a command an implementation is still holding.
  TerminalCommand({
    required this.executable,
    List<String> arguments = const <String>[],
    this.workingDirectory,
    Map<String, String> environment = const <String, String>{},
    this.includeParentEnvironment = true,
    this.runInShell = false,
  }) : arguments = UnmodifiableListView<String>(List<String>.of(arguments)),
       environment = UnmodifiableMapView<String, String>(
         Map<String, String>.of(environment),
       );

  /// Executable to launch.
  final String executable;

  /// Arguments passed to the executable.
  final List<String> arguments;

  /// Directory the child runs in; the parent's when `null`.
  final String? workingDirectory;

  /// Environment entries layered over the inherited environment.
  final Map<String, String> environment;

  /// Whether the parent's environment is inherited.
  final bool includeParentEnvironment;

  /// Whether the host shell interprets the command line.
  final bool runInShell;

  @override
  String toString() => 'TerminalCommand($executable ${arguments.join(' ')})';
}

/// Captured output from a completed terminal invocation.
final class TerminalOutput {
  /// Creates a captured result.
  const TerminalOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  /// Child process exit status.
  final int exitCode;

  /// Captured standard output.
  final String stdout;

  /// Captured standard error.
  final String stderr;

  /// Whether the child exited zero.
  bool get succeeded => exitCode == 0;

  @override
  String toString() => 'TerminalOutput($exitCode)';
}

/// Which stream an interactive write targets.
enum TerminalChannel {
  /// Standard output.
  stdout,

  /// Standard error.
  stderr,
}

/// One interactive write request.
final class TerminalWrite {
  /// Creates a write request.
  const TerminalWrite({
    required this.channel,
    required this.text,
    this.newline = true,
  });

  /// Stream to write to.
  final TerminalChannel channel;

  /// Text to write.
  final String text;

  /// Whether a trailing newline is appended.
  final bool newline;

  @override
  String toString() => 'TerminalWrite(${channel.name}, ${text.length} chars)';
}

/// One interactive read request.
final class TerminalRead {
  /// Creates a read request.
  const TerminalRead({this.prompt});

  /// Prompt shown before reading, when the host supports one.
  final String? prompt;

  @override
  String toString() => 'TerminalRead($prompt)';
}

/// A process-execution and interactive-stdio boundary.
abstract interface class Terminal {
  /// Whether this terminal is attached to an interactive session.
  ///
  /// Non-interactive implementations still accept `write`, but `readLine`
  /// answers `Ok(null)` at end of input rather than blocking.
  bool get interactive;

  /// Runs [command], returning launch failures as `Result` failures.
  ///
  /// A non-zero child exit code is a successfully captured output, not a
  /// transport failure — the caller decides whether that status matters.
  Future<Result<TerminalOutput>> run(TerminalCommand command);

  /// Writes [output] to the session.
  Future<Result<void>> write(TerminalWrite output);

  /// Reads one line, or `Ok(null)` at end of input.
  Future<Result<String?>> readLine([TerminalRead input = const TerminalRead()]);
}

/// Validates an invocation before an implementation launches it.
Result<TerminalCommand> checkTerminalCommand(
  TerminalCommand command, {
  String operation = 'run',
}) {
  if (command.executable.trim().isEmpty) {
    return invalidInput<TerminalCommand>(
      port: PortName.terminal,
      operation: operation,
      field: 'executable',
      message: 'Executable must be non-blank',
    );
  }
  if (command.executable.codeUnits.contains(0)) {
    return invalidInput<TerminalCommand>(
      port: PortName.terminal,
      operation: operation,
      field: 'executable',
      message: 'Executable must not contain a NUL byte',
    );
  }
  for (final String argument in command.arguments) {
    if (argument.codeUnits.contains(0)) {
      return invalidInput<TerminalCommand>(
        port: PortName.terminal,
        operation: operation,
        field: 'arguments',
        message: 'Arguments must not contain a NUL byte',
      );
    }
  }
  for (final String name in command.environment.keys) {
    if (name.trim().isEmpty || name.contains('=')) {
      return invalidInput<TerminalCommand>(
        port: PortName.terminal,
        operation: operation,
        field: 'environment',
        message: 'Environment names must be non-blank and free of "="',
      );
    }
  }
  return Ok<TerminalCommand>(command);
}

/// Validates a captured invocation result before it crosses the seam.
Result<TerminalOutput> checkTerminalOutput(
  TerminalOutput output, {
  String operation = 'run',
}) {
  if (output.exitCode < 0 || output.exitCode > 255) {
    return invalidInput<TerminalOutput>(
      port: PortName.terminal,
      operation: operation,
      field: 'exitCode',
      message: 'Exit code must be within 0..255',
    );
  }
  return Ok<TerminalOutput>(output);
}

/// Validates an interactive write request.
Result<TerminalWrite> checkTerminalWrite(
  TerminalWrite output, {
  String operation = 'write',
}) {
  if (output.text.codeUnits.contains(0)) {
    return invalidInput<TerminalWrite>(
      port: PortName.terminal,
      operation: operation,
      field: 'text',
      message: 'Text must not contain a NUL byte',
    );
  }
  return Ok<TerminalWrite>(output);
}

/// Validates an interactive read request.
Result<TerminalRead> checkTerminalRead(
  TerminalRead input, {
  String operation = 'readLine',
}) {
  final String? prompt = input.prompt;
  if (prompt != null && prompt.codeUnits.contains(0)) {
    return invalidInput<TerminalRead>(
      port: PortName.terminal,
      operation: operation,
      field: 'prompt',
      message: 'Prompt must not contain a NUL byte',
    );
  }
  return Ok<TerminalRead>(input);
}
