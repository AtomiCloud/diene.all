/// The single-source problem type-URI builder (C0 §2).
///
/// Every RFC 9457 `type` URI in the Dart family is minted by [problemTypeUri]
/// — the ONE implementation of the
/// `{scheme}://{host}/docs/{landscape}/{platform}/{service}/{module}/{version}/{id}`
/// template. No consumer ever formats this string itself: the seed apps
/// duplicated the template independently (the failure mode this rule exists to
/// prevent), and a version bump deliberately mints a NEW problem type because
/// `{version}` is part of the contract identity.
///
/// The LPSM service-tree segments arrive via an [ErrorPortal] config block
/// (R4 — never hardcoded); the flutter app sources them from build-time
/// `--dart-define` once `diene_config` lands (documented stacking, see the
/// node note and `docs/`).
library;

/// A single path-segment token (lowercase DNS-label-ish, no slashes).
///
/// Validating segments here keeps the URI canonical and catches misconfigured
/// config blocks at the boundary instead of producing a malformed URI.
typedef ProblemTypeSegment = String;

/// Feeds the problem type-URI template (C0 §2).
///
/// The LPSM service-tree values (`landscape`/`platform`/`service`/`module`) are
/// the row's declaring identity — the same coordinate that derives public
/// hostnames (C0 §9) — so a problem type URI is stable, addressable, and never
/// hand-authored per row.
final class ErrorPortal {
  /// Creates an error-portal config block.
  const ErrorPortal({
    required this.scheme,
    required this.host,
    required this.landscape,
    required this.platform,
    required this.service,
    required this.module,
  });

  /// URI scheme, conventionally `https`.
  final ProblemTypeSegment scheme;

  /// Host serving the problem docs, e.g. `docs.raichu.cluster.atomi.cloud`.
  final ProblemTypeSegment host;

  /// Declaring landscape (LPSM `L` segment).
  final ProblemTypeSegment landscape;

  /// Declaring platform (LPSM `P` segment).
  final ProblemTypeSegment platform;

  /// Service (LPSM `S` segment).
  final ProblemTypeSegment service;

  /// Module (LPSM `M` segment).
  final ProblemTypeSegment module;

  /// Default portal for client-local errors that have no service backend
  /// context (e.g. a pure-Flutter crash before any backend is known).
  ///
  /// Real apps pass their build-time LPSM portal (sourced from `diene_config`)
  /// so local-error type URIs land under the real docs host; this fallback only
  /// keeps the ONE builder usable in isolation and in tests.
  static const ErrorPortal localError = ErrorPortal(
    scheme: 'https',
    host: 'local.atomi.cloud',
    landscape: 'local',
    platform: 'flutter',
    service: 'app',
    module: 'core',
  );
}

/// Thrown when a problem type-URI segment is empty or contains a `/`.
class InvalidProblemTypeSegmentError extends ArgumentError {
  InvalidProblemTypeSegmentError(String name, Object? value)
    : super.value(value, name, 'must be a non-empty single path segment');
}

void _check(String name, ProblemTypeSegment segment) {
  if (segment.isEmpty || segment.contains('/')) {
    throw InvalidProblemTypeSegmentError(name, segment);
  }
}

/// Builds the RFC 9457 `type` URI from an [ErrorPortal] config block.
///
/// This is the single source of the type-URI template (C0 §2). Every problem —
/// catalog entries, runtime envelopes, local errors — resolves its `type`
/// through this function.
///
/// ```dart
/// final uri = problemTypeUri(
///   portal: portal,
///   version: 'v1',
///   id: 'entity-not-found',
/// );
/// // https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/v1/entity-not-found
/// ```
String problemTypeUri({
  required ErrorPortal portal,
  required ProblemTypeSegment version,
  required ProblemTypeSegment id,
}) {
  _check('scheme', portal.scheme);
  _check('host', portal.host);
  _check('landscape', portal.landscape);
  _check('platform', portal.platform);
  _check('service', portal.service);
  _check('module', portal.module);
  _check('version', version);
  _check('id', id);
  return '${portal.scheme}://${portal.host}/docs/${portal.landscape}'
      '/${portal.platform}/${portal.service}/${portal.module}/$version/$id';
}
