/// The failure vocabulary every `diene_interfaces` seam reports through.
///
/// The Dart family fixes the `Result` error channel to `Problem`
/// (`package:diene_problems`), so this library has no `PortError` exception
/// class of its own. What it does own is the *vocabulary* — which seam failed
/// ([PortName]) and how ([PortErrorCode]) — plus [portProblem], the single
/// place that turns that vocabulary into an RFC 9457 envelope.
///
/// Every `type` URI is minted by `problemTypeUri` from `package:diene_problems`
/// (C0 §2: exactly ONE builder, never a hand-formatted string).
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Which seam produced a failure.
enum PortName {
  /// The `System` process/clock boundary.
  system,

  /// The `Vfs` filesystem boundary.
  vfs,

  /// The `Terminal` process-execution and stdio boundary.
  terminal,

  /// The `LoggerSink` structured-log emit boundary.
  logging,

  /// The `MetricsCollector` sample emit boundary.
  metrics,
}

/// How a seam failed.
///
/// The vocabulary mirrors the `lib/bun/interfaces` sibling's `PortErrorCode`
/// so a cross-language reader recognises the same failure taxonomy.
enum PortErrorCode {
  /// The target already exists.
  alreadyExists('already-exists', 409),

  /// The boundary was already closed.
  closed('closed', 409),

  /// A non-recursive delete hit a non-empty directory.
  directoryNotEmpty('directory-not-empty', 409),

  /// The caller supplied input the contract forbids.
  invalidInput('invalid-input', 400),

  /// A host I/O failure with no more specific code.
  io('io', 500),

  /// A directory operation was aimed at a non-directory.
  notADirectory('not-a-directory', 400),

  /// A file operation was aimed at a non-file.
  notAFile('not-a-file', 400),

  /// The target does not exist.
  notFound('not-found', 404),

  /// The host refused the operation.
  permissionDenied('permission-denied', 403),

  /// The operation exceeded its budget.
  timeout('timeout', 504, recoverable: true),

  /// The boundary is temporarily unavailable.
  unavailable('unavailable', 503, recoverable: true),

  /// A fake or adapter was called without a scripted response.
  unexpectedCall('unexpected-call', 500),

  /// The boundary does not implement the operation.
  unsupported('unsupported', 501);

  const PortErrorCode(this.wireId, this.status, {this.recoverable = false});

  /// Stable kebab-case identifier used in the problem type URI and `data`.
  final String wireId;

  /// HTTP status the RFC 9457 envelope carries for this code.
  final int status;

  /// Whether a caller may sensibly retry (C0 §2 `recoverable` extension).
  final bool recoverable;
}

/// Contract version segment of every problem type URI minted here.
///
/// `{version}` is part of the C0 §2 contract identity: bumping it deliberately
/// mints NEW problem types rather than redefining the existing ones.
const String interfacesProblemVersion = 'v1';

/// Builds the RFC 9457 envelope for a seam failure.
///
/// The `type` URI is produced by `problemTypeUri` — the ONE C0 §2 builder —
/// from [portal], which defaults to `ErrorPortal.localError` because these are
/// client-local boundary failures with no backend service context. An
/// application that has its real LPSM portal (from `diene_config`) passes it in
/// so the URIs land under the real docs host.
Problem portProblem({
  required PortName port,
  required PortErrorCode code,
  required String operation,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Problem(
  type: problemTypeUri(
    portal: portal,
    version: interfacesProblemVersion,
    id: '${port.name}-${code.wireId}',
  ),
  title: message,
  status: code.status,
  detail: '${port.name}.$operation: $message',
  recoverable: code.recoverable,
  data: <String, Object?>{
    'port': port.name,
    'code': code.wireId,
    'operation': operation,
    ...details,
  },
);

/// Builds an `Err` carrying [portProblem]'s envelope.
///
/// Sugar for the overwhelmingly common seam shape — every fallible member
/// returns a failure as a value, never as a thrown exception.
Err<T> portFailure<T>({
  required PortName port,
  required PortErrorCode code,
  required String operation,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Err<T>(
  portProblem(
    port: port,
    code: code,
    operation: operation,
    message: message,
    portal: portal,
    details: details,
  ),
);

/// Builds an invalid-input failure for [operation] on [port].
Err<T> invalidInput<T>({
  required PortName port,
  required String operation,
  required String field,
  required String message,
}) => portFailure<T>(
  port: port,
  code: PortErrorCode.invalidInput,
  operation: operation,
  message: message,
  details: <String, Object?>{'field': field},
);
