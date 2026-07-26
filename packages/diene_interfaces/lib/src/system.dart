/// The ambient process boundary: environment, working directory, clock, delay.
library;

import 'package:diene_result/diene_result.dart';

/// The process and clock boundary used by portable Dart libraries.
///
/// This seam covers the process's OWN ambient state. Spawning child processes
/// is the `Terminal` seam's job, so a consumer that only needs a fakeable clock
/// never has to accept a process runner as well.
///
/// Implementations report host failures as `Result` values. They must not
/// translate an expected failure into a thrown exception.
abstract interface class System {
  /// Looks up one process environment variable.
  ///
  /// An absent variable is `Ok(null)`, not a failure — absence is a normal
  /// answer, and only a host lookup fault is an error.
  Result<String?> environment(String name);

  /// Returns the current working directory as an absolute path.
  Result<String> currentDirectory();

  /// Returns the current instant in UTC.
  Result<DateTime> nowUtc();

  /// Delays without exposing the host timer implementation.
  Future<Result<void>> delay(Duration duration);
}
