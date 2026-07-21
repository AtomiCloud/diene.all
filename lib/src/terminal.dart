import 'dart:collection';

import 'package:diene_result/diene_result.dart';

/// One process invocation requested through [Terminal].
final class TerminalCommand {
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

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final bool includeParentEnvironment;
  final bool runInShell;
}

/// Captured output from a completed terminal invocation.
final class TerminalOutput {
  const TerminalOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get succeeded => exitCode == 0;
}

/// A process-execution boundary.
abstract interface class Terminal {
  /// Runs [command], returning launch failures as [Result] failures.
  ///
  /// A non-zero child exit code is a successfully captured [TerminalOutput],
  /// not a transport failure.
  Future<Result<TerminalOutput>> run(TerminalCommand command);
}
