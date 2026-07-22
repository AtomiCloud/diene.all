/// E4-final integration manifest — the machine-checkable map of what the final
/// Flutter assembly will wire in, and what is HELD pending an accepted
/// `lib/dart/e2e` sha.
///
/// This file carries NO behaviour beyond describing the integration plan; it
/// exists so the hold is expressed in code (and asserted by a test) rather than
/// only in prose. When `lib/dart/e2e` obtains an independently ACCEPTED sha, the
/// T13-REBASE pass flips each held point to satisfied by swapping the local
/// optimistic bridge for the named diene package and clearing its [held] flag.
library;

/// A single integration point in the E4-final assembly.
final class E4IntegrationPoint {
  const E4IntegrationPoint({
    required this.localBridge,
    required this.dienePackage,
    required this.held,
    required this.note,
  });

  /// The flutter-base local optimistic bridge that stands in today.
  final String localBridge;

  /// The diene package (delivered via `lib/dart/e2e`) that replaces it.
  final String dienePackage;

  /// Whether this point is still held (true = awaiting accepted e2e sha).
  final bool held;

  /// Human-readable rationale / scope note.
  final String note;
}

/// The frozen accepted parent basis for the whole assembly.
const String flutterBaseAcceptedSha =
    '891c5c9bad5c81b5d1011ac75143489b927cee94';

/// Primary hold reason reported by this node (see node-status flutter-e4.md).
const String primaryHoldReason =
    'lib/dart/e2e has no accepted sha yet (state: blocked); the diene package '
    'surface it assembles cannot be wired until that sha is independently '
    'ACCEPTED. flutter-base (891c5c9) and observability (done) are satisfied and '
    'are wired live in this scaffold.';

/// The E4-final integration map.
///
/// Every point whose [dienePackage] comes from `lib/dart/e2e` is [held]; the
/// observability wiring point stands live because it needs only flutter-base +
/// the observability payload.
const List<E4IntegrationPoint> e4IntegrationMap = <E4IntegrationPoint>[
  E4IntegrationPoint(
    localBridge: 'lib/core/result.dart (Result/Success/Failure/Problem)',
    dienePackage: 'diene_result (via lib/dart/e2e)',
    held: true,
    note:
        'Replace the optimistic Result bridge with the accepted diene_result '
        'sealed Result once e2e lands.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/core/problem_catalog.dart + lib/core/local_error.dart',
    dienePackage: 'diene_problems (via lib/dart/e2e)',
    held: true,
    note: 'Route problem construction/catalogue through diene_problems.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/config/app_config.dart loaders',
    dienePackage: 'diene_config + diene_core_utils (via lib/dart/e2e)',
    held: true,
    note:
        'Adopt diene_config typed loaders + core-utils temporal/identity '
        'helpers in place of hand-rolled parsing.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/auth/*_auth_gateway.dart + session_controller.dart',
    dienePackage: 'diene_auth_engine (via lib/dart/e2e)',
    held: true,
    note: 'Drive session/refresh through the accepted auth engine.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/generated/service/** (retrofit fallback client)',
    dienePackage: 'diene_api_engine (via lib/dart/e2e)',
    held: true,
    note: 'Swap the generated fallback client for the api engine surface.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/integration/observability_wiring.dart',
    dienePackage: 'observability payload LPSM standard (state: done)',
    held: false,
    note:
        'STANDS LIVE: LPSM labels projected from AppIdentityConfig; concrete '
        'OTel/Faro exporter transport lands with e2e (see SignalSink).',
  ),
];

/// True when every held point has been cleared (i.e. e2e is fully wired).
bool get e4IntegrationComplete =>
    e4IntegrationMap.every((E4IntegrationPoint p) => !p.held);

/// The held points still awaiting the accepted e2e sha.
List<E4IntegrationPoint> get e4HeldPoints =>
    e4IntegrationMap.where((E4IntegrationPoint p) => p.held).toList();
