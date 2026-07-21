import 'package:diene_result/diene_result.dart';

/// The process and clock boundary used by portable Dart libraries.
///
/// Implementations report host failures as [Result] values. They must not
/// translate a failure into a thrown exception.
abstract interface class System {
  /// Looks up one process environment variable.
  Result<String?> environment(String name);

  /// Returns the current working directory as an absolute path.
  Result<String> currentDirectory();

  /// Returns the current instant in UTC.
  Result<DateTime> nowUtc();

  /// Delays without exposing the host timer implementation.
  Future<Result<void>> delay(Duration duration);
}
