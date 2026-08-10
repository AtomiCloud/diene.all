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

/// The `data` key that carries a config problem's canonical wire id.
///
/// It is reserved: [configProblem] mints it from the requested
/// [ConfigProblemCode] and refuses caller-supplied `details` that would set it,
/// so the payload can never disagree with the code the envelope was minted for.
const String configProblemCodeKey = 'code';

/// The `data` key stamping that an envelope was minted by [configProblem].
///
/// Provenance CANNOT ride on the `type` URI. Its LPSM segments come from the
/// caller-supplied [ErrorPortal] (scheme/host/landscape/platform/service/module
/// are all free), so a foreign minter can reproduce any
/// `…/{version}/{config wire id}` suffix under its own host — the type URI
/// therefore proves nothing about which *package* built the envelope. This
/// discriminator lives in the payload instead, carries a package-owned constant
/// ([configProblemValue]) that travels identically across every supported
/// portal, and is reserved against caller `details` the same way as
/// [configProblemCodeKey]. Only this package mints it, so a foreign envelope —
/// even one that coincidentally carries a valid config `code` and a matching
/// type-URI suffix — lacks it and classifies as `None`.
const String configProblemProvenanceKey = 'x-diene-config-provenance';

/// The constant [configProblemProvenanceKey] value: this package's identity and
/// its contract version. The embedded `configProblemVersion` makes the marker a
/// per-version identity, so an envelope minted under a different contract
/// version is not read as this version's vocabulary.
const String configProblemValue =
    'atomicloud/diene_config@$configProblemVersion';

/// Builds the RFC 9457 envelope for a `diene_config` failure.
///
/// The `type` URI is produced by `problemTypeUri` from [portal], which defaults
/// to `ErrorPortal.localError` because these are client-local input failures
/// with no backend service context. An application that already knows its real
/// LPSM portal passes it in so the URIs land under the real docs host.
///
/// [configProblemCodeKey] and [configProblemProvenanceKey] are reserved:
/// `details` MUST NOT carry either. A caller cannot ask for
/// [ConfigProblemCode.schemaInvalid] while sneaking `code: 'source_unreadable'`
/// through `details` to mislabel the envelope, nor forge the provenance marker
/// a foreign envelope should never have — both throw [ArgumentError] rather than
/// minting a spoofable envelope. This keeps `data.code` a faithful mirror of the
/// requested code and the provenance marker a discriminator only this package
/// mints, which is what [configProblemCode] authenticates against.
///
/// Every failure here is a deterministic function of its input, so the envelope
/// is never marked `recoverable`.
Problem configProblem({
  required ConfigProblemCode code,
  required String message,
  ErrorPortal portal = ErrorPortal.localError,
  Map<String, Object?> details = const <String, Object?>{},
}) {
  const List<String> reserved = <String>[
    configProblemCodeKey,
    configProblemProvenanceKey,
  ];
  for (final String key in reserved) {
    if (details.containsKey(key)) {
      throw ArgumentError.value(
        details,
        'details',
        'must not set the reserved "$key" key — configProblem mints it '
            '(code ${code.wireId}) so provenance stays authenticated',
      );
    }
  }
  return Problem(
    type: problemTypeUri(
      portal: portal,
      version: configProblemVersion,
      id: code.wireId,
    ),
    title: message,
    status: code.status,
    detail: 'config.${code.wireId}: $message',
    // Reserved fields last: a defence-in-depth guarantee that the canonical id
    // and provenance marker win even if the reservation check above is relaxed.
    data: <String, Object?>{
      ...details,
      configProblemCodeKey: code.wireId,
      configProblemProvenanceKey: configProblemValue,
    },
  );
}

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
/// Provenance is decided by the reserved [configProblemProvenanceKey] marker —
/// the config-minted discriminator only [configProblem] stamps — NOT by the
/// `type` URI (whose portal segments are caller-supplied and reproducible) nor
/// by a bare `data.code` (which any envelope can copy). An envelope is
/// config-owned only when it carries [configProblemValue] under that key; its
/// [configProblemCodeKey] is then authoritative, because that field is reserved
/// against forgery on the mint path.
///
/// Returns `None` for an envelope minted elsewhere — notably the
/// `diene_core_utils` coercion problems the loader propagates UNCHANGED, whose
/// `data.code` belongs to that package's own vocabulary. A foreign problem that
/// coincidentally copies a config-shaped `data.code`, or even reproduces the
/// config type-URI suffix under a foreign host, is likewise `None`: it never
/// carries this package's provenance marker. An envelope minted under a
/// different contract version carries a different marker value and is `None`
/// too. Callers therefore branch on presence rather than assuming every failure
/// is config-owned.
Option<ConfigProblemCode> configProblemCode(Problem problem) {
  if (problem.data[configProblemProvenanceKey] != configProblemValue) {
    return const None<ConfigProblemCode>();
  }
  final Object? code = problem.data[configProblemCodeKey];
  for (final ConfigProblemCode candidate in ConfigProblemCode.values) {
    if (candidate.wireId == code) {
      return Some<ConfigProblemCode>(candidate);
    }
  }
  return const None<ConfigProblemCode>();
}
