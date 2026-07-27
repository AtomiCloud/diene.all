/// The failure vocabulary `diene_config` reports through.
///
/// The Dart family fixes the `Result` error channel to `Problem`
/// (`package:diene_problems`), so this library owns no exception class for its
/// expected failures — it owns the *vocabulary* ([ConfigProblemCode]) and
/// [configProblem], the single place that turns it into an RFC 9457 envelope.
///
/// Every `type` URI is minted by `problemTypeUri` — the ONE C0 §2 builder —
/// never a hand-formatted string. Override-ingress failures are NOT re-minted
/// here: `environmentToNestedMap` already returns a `Problem` from
/// `diene_core_utils`, and the loader propagates that envelope unchanged so its
/// original coercion vocabulary survives.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Contract version segment of every config problem type URI.
///
/// `{version}` is part of the C0 §2 contract identity: bumping it deliberately
/// mints NEW problem types rather than redefining the existing ones.
const String configProblemVersion = 'v1';

/// How a `diene_config` operation failed.
///
/// The [wireId] is the stable snake_case id embedded in the problem type URI
/// and `data`; it matches the `^[a-z][a-z0-9_]*$` wire-id law enforced by
/// `problemTypeUri`.
enum ConfigProblemCode {
  /// A configuration layer could not be read or its YAML could not be parsed.
  sourceUnreadable('source_unreadable', 422),

  /// A configuration layer parsed but its root is not a map.
  sourceNotAMap('source_not_a_map', 422),

  /// The final merged configuration failed schema validation.
  schemaInvalid('schema_invalid', 422),

  /// No build-time landscape identity was supplied.
  landscapeMissing('landscape_missing', 400);

  const ConfigProblemCode(this.wireId, this.status);

  /// Stable snake_case identifier used in the problem type URI and `data`.
  final String wireId;

  /// HTTP status the RFC 9457 envelope carries for this code.
  final int status;
}

/// Builds the RFC 9457 envelope for a `diene_config` failure.
///
/// The `type` URI is produced by `problemTypeUri` from [portal], which defaults
/// to `ErrorPortal.localError` because these are client-local input failures
/// with no backend service context. An application that already knows its real
/// LPSM portal passes it in so the URIs land under the real docs host.
///
/// Every failure here is a deterministic function of its input, so the envelope
/// is never marked `recoverable`.
Problem configProblem({
  required ConfigProblemCode code,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Problem(
  type: problemTypeUri(
    portal: portal,
    version: configProblemVersion,
    id: code.wireId,
  ),
  title: message,
  status: code.status,
  detail: 'config.${code.wireId}: $message',
  data: <String, Object?>{'code': code.wireId, ...details},
);

/// Builds an `Err` carrying [configProblem]'s envelope.
///
/// Sugar for the common shape — every fallible member returns a failure as a
/// value, never as a thrown exception.
Err<T> configFailure<T>({
  required ConfigProblemCode code,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Err<T>(
  configProblem(code: code, message: message, portal: portal, details: details),
);

/// Reads the [ConfigProblemCode] a `diene_config` envelope carries.
///
/// Returns `None` for an envelope minted elsewhere — notably the
/// `diene_core_utils` coercion problems the loader propagates UNCHANGED, whose
/// `data.code` belongs to that package's own vocabulary. Callers therefore
/// branch on presence rather than assuming every failure is config-owned.
Option<ConfigProblemCode> configProblemCode(Problem problem) {
  final Object? code = problem.data['code'];
  for (final ConfigProblemCode candidate in ConfigProblemCode.values) {
    if (candidate.wireId == code) {
      return Some<ConfigProblemCode>(candidate);
    }
  }
  return const None<ConfigProblemCode>();
}
