/// The build-time landscape identity accessor.
///
/// The landscape is IDENTITY, stamped into the binary at build time. On mobile
/// the store track IS the landscape. This is an accessor, never a detector: it
/// reads one `--dart-define` and nothing else — no hostname sniffing, no
/// runtime environment lookup, no remote probe. A build that forgot the define
/// is a build with no identity, and says so as a value.
library;

import 'package:diene_result/diene_result.dart';

import 'config_problem.dart';

/// The `--dart-define` key carrying the landscape identity.
const String landscapeDefineKey = 'DIENE_LANDSCAPE';

/// Supplies the build-time landscape identity.
abstract interface class LandscapeSource {
  /// Returns the raw, untrimmed landscape value.
  String read();
}

/// Reads the landscape from `--dart-define=DIENE_LANDSCAPE=<track>`.
///
/// [value] defaults to the compile-time constant so a real build needs no
/// wiring; a test injects its own value instead. `String.fromEnvironment` is
/// resolved at COMPILE time, which is exactly why this is an accessor: the
/// value physically cannot change at runtime.
final class DartDefineLandscapeSource implements LandscapeSource {
  /// Creates a source reading the build-time define, or an explicit [value].
  const DartDefineLandscapeSource({
    this.value = const String.fromEnvironment(landscapeDefineKey),
  });

  /// The landscape identity this source reports.
  final String value;

  @override
  String read() => value;
}

/// Returns the build-time landscape identity, or a `Problem` when absent.
///
/// A blank or whitespace-only define is treated as ABSENT rather than as the
/// empty landscape, matching the C0 §3 blank-is-unset rule that governs every
/// other define this package reads.
Result<String> landscape({
  LandscapeSource source = const DartDefineLandscapeSource(),
}) {
  final String value = source.read().trim();
  if (value.isEmpty) {
    return configFailure<String>(
      code: ConfigProblemCode.landscapeMissing,
      message:
          'no landscape identity; build with '
          '--dart-define=$landscapeDefineKey=<track>',
      details: <String, Object?>{'define': landscapeDefineKey},
    );
  }
  return Ok<String>(value);
}
