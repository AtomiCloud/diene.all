/// The failure vocabulary every fallible `diene_core_utils` member reports
/// through.
///
/// The Dart family fixes the `Result` error channel to `Problem`
/// (`package:diene_problems`), so this library owns no exception class of its
/// own. What it does own is the *vocabulary* — which utility surface failed
/// ([UtilName]) and how ([UtilErrorCode]) — plus [utilProblem], the single
/// place that turns that vocabulary into an RFC 9457 envelope.
///
/// Every `type` URI is minted by `problemTypeUri` from `package:diene_problems`
/// (C0 §2: exactly ONE builder, never a hand-formatted string). The vocabulary
/// deliberately mirrors `diene_interfaces`' `PortName`/`PortErrorCode` shape so
/// a cross-language reader recognises the same failure taxonomy.
library;

import 'package:diene_problems/diene_problems.dart';
import 'package:diene_result/diene_result.dart';

/// Which utility surface produced a failure.
enum UtilName {
  /// Slug and namespaced-key composition.
  slug,

  /// Environment-scalar and nested-map coercion.
  coercion,

  /// Deterministic config projection.
  record,

  /// C0 temporal and timezone wire codecs.
  wire,

  /// Bounded-concurrency mapping.
  concurrency,

  /// Duration-based waiting.
  timing,

  /// Text helpers over the `Vfs` seam.
  vfs;

  /// Stable snake_case identifier used in the problem type URI and `data`.
  ///
  /// R-E14 wire-id law: every id must match `^[a-z][a-z0-9_]*$`, the pattern
  /// the single-source `problemTypeUri` builder enforces. The enum names here
  /// are already single lowercase words, so [name] is the wire id verbatim —
  /// there is no separate spelling that could drift from it.
  String get wireId => name;
}

/// How a utility surface failed.
enum UtilErrorCode {
  /// The caller supplied input the contract forbids.
  invalidInput('invalid_input', 400),

  /// The input violates the C0 wire grammar for its domain.
  invalidFormat('invalid_format', 400),

  /// Two normalised inputs collapsed onto the same identity.
  conflict('conflict', 409),

  /// The input graph cannot be projected (for example, it is cyclic).
  unprojectable('unprojectable', 422),

  /// A seam this helper delegates to reported a failure.
  delegated('delegated', 500);

  const UtilErrorCode(this.wireId, this.status);

  /// Stable snake_case identifier used in the problem type URI and `data`.
  final String wireId;

  /// HTTP status the RFC 9457 envelope carries for this code.
  final int status;

  /// Whether a caller may sensibly retry (C0 §2 `recoverable` extension).
  ///
  /// Always `false`, and deliberately not a per-code flag: every failure this
  /// library reports is a deterministic function of its input, so retrying the
  /// identical call cannot change the outcome. A genuinely retryable failure —
  /// a timeout or an unavailable host — can only come from the `Vfs` seam, and
  /// [readVfsText] and friends propagate that seam's envelope UNCHANGED, so its
  /// own `recoverable: true` survives rather than being overwritten here.
  bool get recoverable => false;
}

/// Contract version segment of every problem type URI minted here.
///
/// `{version}` is part of the C0 §2 contract identity: bumping it deliberately
/// mints NEW problem types rather than redefining the existing ones.
const String coreUtilsProblemVersion = 'v1';

/// Builds the RFC 9457 envelope for a utility failure.
///
/// The `type` URI is produced by `problemTypeUri` — the ONE C0 §2 builder —
/// from [portal], which defaults to `ErrorPortal.localError` because these are
/// client-local input failures with no backend service context. An application
/// that has its real LPSM portal (from `diene_config`) passes it in so the URIs
/// land under the real docs host.
Problem utilProblem({
  required UtilName util,
  required UtilErrorCode code,
  required String operation,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Problem(
  type: problemTypeUri(
    portal: portal,
    version: coreUtilsProblemVersion,
    id: '${util.wireId}_${code.wireId}',
  ),
  title: message,
  status: code.status,
  detail: '${util.wireId}.$operation: $message',
  recoverable: code.recoverable,
  data: <String, Object?>{
    'util': util.wireId,
    'code': code.wireId,
    'operation': operation,
    ...details,
  },
);

/// Builds an `Err` carrying [utilProblem]'s envelope.
///
/// Sugar for the overwhelmingly common shape — every fallible member returns a
/// failure as a value, never as a thrown exception.
Err<T> utilFailure<T>({
  required UtilName util,
  required UtilErrorCode code,
  required String operation,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) => Err<T>(
  utilProblem(
    util: util,
    code: code,
    operation: operation,
    message: message,
    portal: portal,
    details: details,
  ),
);

/// Builds an invalid-input failure naming the offending [field].
Err<T> invalidUtilInput<T>({
  required UtilName util,
  required String operation,
  required String field,
  required String message,
}) => utilFailure<T>(
  util: util,
  code: UtilErrorCode.invalidInput,
  operation: operation,
  message: message,
  details: <String, Object?>{'field': field},
);

/// Builds an invalid-format failure naming the rejected [value] and its
/// expected C0 wire grammar.
Err<T> invalidWireFormat<T>({
  required String operation,
  required String expected,
  required String value,
}) => utilFailure<T>(
  util: UtilName.wire,
  code: UtilErrorCode.invalidFormat,
  operation: operation,
  message: 'expected $expected',
  details: <String, Object?>{'expected': expected, 'value': value},
);
