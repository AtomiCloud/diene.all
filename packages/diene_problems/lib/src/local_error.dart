/// LocalError — wraps unexpected client-side exceptions into a Problem
/// (goal: dart frontends wrap unexpected exceptions into a `LocalError` Problem,
/// message + stacktrace in `data`, rendered by a Problem visualizer shipped in
/// flutter-base).
///
/// The type URI flows through the single-source builder ([problemTypeUri]) so
/// even local errors share one identity shape; the `data` payload carries the
/// message and stack trace the visualizer surfaces.
library;

import 'problem.dart';
import 'problem_type_uri.dart';

/// Receives unexpected problems captured by [LocalError].
///
/// In production this forwards to the frontend telemetry/Faro path (Faro owns
/// runtime emission; this seam stays owned by the interfaces/telemetry layer —
/// see node note). Tests inject a recording sink.
abstract interface class ErrorSink {
  /// Captures [problem] for reporting.
  Future<void> capture(Problem problem);
}

/// An [ErrorSink] that discards every capture.
final class NoopErrorSink implements ErrorSink {
  /// Creates a no-op sink.
  const NoopErrorSink();

  @override
  Future<void> capture(Problem problem) async {}
}

/// Wraps unexpected exceptions into a `LocalError` Problem.
///
/// ```dart
/// final Problem problem = await LocalError(sink).wrap(error, stack);
/// ```
final class LocalError {
  /// Creates a local-error wrapper writing captures to [sink].
  const LocalError(this.sink, {this.portal = ErrorPortal.localError});

  /// Destination for captured local-error problems.
  final ErrorSink sink;

  /// Portal used to build the local-error type URI.
  final ErrorPortal portal;

  /// Wraps [error] + [stackTrace] into a `LocalError` Problem, captures it on
  /// [sink], and returns it.
  Future<Problem> wrap(Object error, StackTrace stackTrace) async {
    final String message = error.toString();
    final Problem problem = Problem(
      type: problemTypeUri(portal: portal, version: 'v1', id: 'local_error'),
      title: 'Local Error',
      status: 500,
      detail: message,
      recoverable: false,
      data: <String, Object?>{
        'message': message,
        'stackTrace': stackTrace.toString(),
      },
    );
    await sink.capture(problem);
    return problem;
  }
}
