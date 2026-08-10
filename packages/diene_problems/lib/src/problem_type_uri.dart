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

/// Thrown when a problem type-URI segment violates its pattern (R-E14 for ids).
class InvalidProblemTypeSegmentError extends ArgumentError {
  InvalidProblemTypeSegmentError(String name, Object? value)
    : super.value(
        value,
        name,
        'must be a non-empty single path segment matching its contract pattern',
      );
}

/// Matches an LPSM path segment: a DNS-label-ish token, no slashes.
///
/// Byte-identical in intent to the published `@atomicloud/diene.problems`
/// builder's `segmentPattern`, so the same portal is accepted or rejected in
/// both languages.
final RegExp problemSegmentPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$');

/// Matches the RFC 9457 WIRE problem id: **snake_case** (R-E14, C0 §7).
///
/// R-E14 amended C0 §7: the definition/factory name stays PascalCase
/// (`AppHandoffExpired`) while the WIRE id is `app_handoff_expired`. This is the
/// same regex the published `@atomicloud/diene.problems@1.0.0` builder enforces
/// (`problemIdPattern`), so a wire id minted by one language family is
/// accepted by all four. A kebab id — the pre-R-E14 spelling that still appears
/// in the frozen C0 fixture's SAMPLE values — is rejected here on purpose; see
/// `test/conformance/c0_wire_id_variance_test.dart` for the pinned pair.
final RegExp problemWireIdPattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// Matches the contract version segment, e.g. `v1` (bun parity).
final RegExp problemVersionPattern = RegExp(r'^v[0-9]+$');

void _check(String name, ProblemTypeSegment segment, [RegExp? pattern]) {
  final RegExp effective = pattern ?? problemSegmentPattern;
  if (segment.isEmpty ||
      segment.contains('/') ||
      !effective.hasMatch(segment)) {
    throw InvalidProblemTypeSegmentError(name, segment);
  }
}

void _checkHost(ProblemTypeSegment scheme, ProblemTypeSegment host) {
  if (host.isEmpty ||
      host.trim() != host ||
      RegExp(r'[/\\\s@?#]').hasMatch(host)) {
    throw InvalidProblemTypeSegmentError('host', host);
  }
  final Uri? origin = Uri.tryParse('$scheme://$host/');
  if (origin == null ||
      origin.authority != host ||
      origin.userInfo.isNotEmpty ||
      origin.path != '/' ||
      origin.hasQuery ||
      origin.hasFragment) {
    throw InvalidProblemTypeSegmentError('host', host);
  }
}

/// Builds the RFC 9457 `type` URI from an [ErrorPortal] config block.
///
/// This is the single source of the type-URI template (C0 §2). Every problem —
/// catalog entries, runtime envelopes, local errors — resolves its `type`
/// through this function.
///
/// [id] is the WIRE id and must be snake_case per R-E14
/// ([problemWireIdPattern]); [version] must be `v<n>`.
///
/// ```dart
/// final uri = problemTypeUri(
///   portal: portal,
///   version: 'v1',
///   id: 'entity_not_found',
/// );
/// // https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/v1/entity_not_found
/// ```
String problemTypeUri({
  required ErrorPortal portal,
  required ProblemTypeSegment version,
  required ProblemTypeSegment id,
}) {
  _check('scheme', portal.scheme);
  _checkHost(portal.scheme, portal.host);
  _check('landscape', portal.landscape);
  _check('platform', portal.platform);
  _check('service', portal.service);
  _check('module', portal.module);
  _check('version', version, problemVersionPattern);
  _check('id', id, problemWireIdPattern);
  return '${portal.scheme}://${portal.host}/docs/${portal.landscape}'
      '/${portal.platform}/${portal.service}/${portal.module}/$version/$id';
}

/// Normalizes a pre-R-E14 KEBAB wire id to its R-E14 snake_case form.
///
/// The frozen C0 release's problem fixture predates R-E14 and still carries
/// kebab SAMPLE ids (`entity-not-found`). The fixture bytes are authoritative
/// for the envelope vocabulary and the type-URI TEMPLATE and are never
/// rewritten in this package (the correction is owed at the release owner), so
/// consumers project the sample ids through this ONE documented transformation
/// instead of hand-editing vectors. It is deliberately narrow: only `-` → `_`.
String r14WireId(String legacyId) => legacyId.replaceAll('-', '_');
