/// E4-final integration manifest — the machine-checkable map of what the final
/// Flutter assembly wires in.
///
/// This file carries NO behaviour beyond describing the integration state; it
/// exists so the record is expressed in code (and asserted by a test) rather
/// than only in prose. It is DESCRIPTIVE: nothing in `lib/` reads [held] as a
/// runtime wiring signal — the aggregators below and the manifest test are its
/// only readers.
///
/// The six published diene packages were declared from pub.dev (W4, `15c8185`),
/// NOT delivered through a `lib/dart/e2e` path dependency. That dissolved the
/// original hold condition — each [held] flag was defined as "awaiting an
/// accepted `lib/dart/e2e` sha", and that sha is no longer how the surface
/// arrives — so every point is cleared. Where a point's transport swap is still
/// owed (auth/api engines), its [note] says so explicitly and the work is
/// recorded on the node for assignment; the flag records the dissolved await,
/// and the note carries the residual meaning.
library;

/// A single integration point in the E4-final assembly.
final class E4IntegrationPoint {
  const E4IntegrationPoint({
    required this.localBridge,
    required this.dienePackage,
    required this.held,
    required this.note,
  });

  /// The flutter-base local optimistic bridge that stood in (deleted or
  /// retained as the [note] records).
  final String localBridge;

  /// The published diene package that replaces it.
  final String dienePackage;

  /// Whether this point is still held (true = the integration await is unmet).
  ///
  /// All points are cleared: the await was an accepted `lib/dart/e2e` sha, and
  /// the packages instead landed on pub.dev (declared by W4 at `15c8185`).
  final bool held;

  /// Human-readable rationale / scope note — the authoritative description of
  /// what is done and what, if anything, remains owed.
  final String note;
}

/// The frozen accepted parent basis for the whole assembly.
const String flutterBaseAcceptedSha =
    '891c5c9bad5c81b5d1011ac75143489b927cee94';

/// Primary integration-status reason reported by this node.
///
/// No hold remains: the diene surface is integrated from published pub.dev
/// packages (declared by W4 at `15c8185`), not from a `lib/dart/e2e` sha, so the
/// original await is dissolved. The only outstanding work is the auth/api engine
/// TRANSPORT swaps (and full diene_config typed-loader adoption), recorded on
/// the node for assignment (see those points' notes); they are follow-ons, not
/// holds on this assembly.
const String primaryHoldReason =
    'No hold remains: the six diene packages are integrated from pub.dev '
    '(declared by W4 at 15c8185), not from a lib/dart/e2e sha, so the original '
    'await is dissolved. flutter-base (891c5c9) and observability (done) remain '
    'satisfied and wired live. Outstanding follow-ons are the diene_auth_engine '
    'and diene_api_engine transport swaps and full diene_config typed-loader '
    'adoption, each recorded on the node for assignment — not holds here.';

/// The E4-final integration map.
///
/// Every point is cleared ([held] false): the published diene surface is
/// declared and this node's callers speak its `Result`/`Problem` contract. A
/// point whose transport swap is still owed says so in its [note].
const List<E4IntegrationPoint> e4IntegrationMap = <E4IntegrationPoint>[
  E4IntegrationPoint(
    localBridge:
        'lib/core/result.dart (deleted; was the local Result hierarchy + Problem)',
    dienePackage: 'diene_result 1.0.0 (pub.dev)',
    held: false,
    note:
        'DONE: the local Result bridge is DELETED; every Result caller now uses '
        'the published sealed Result / Ok / Err from diene_result 1.0.0, whose '
        'error channel is the diene_problems Problem envelope.',
  ),
  E4IntegrationPoint(
    localBridge:
        'lib/core/problem_catalog.dart + lib/core/local_error.dart (both deleted)',
    dienePackage: 'diene_problems 0.1.1 (pub.dev)',
    held: false,
    note:
        'DONE: both local bridges are DELETED; Problem, LocalError/ErrorSink/'
        'NoopErrorSink, and the CatalogEntry row type now come from '
        'diene_problems 0.1.1. The runtime endpoint classifier (ProblemCatalog '
        'with classify()) is retained locally in '
        'lib/problems/catalog_classification.dart — it has no published '
        'counterpart, since the published ProblemCatalog is the CRD-export '
        'producer, not a runtime classifier.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/config/app_config.dart loaders',
    dienePackage: 'diene_config 1.0.0 + diene_core_utils 1.0.1 (pub.dev)',
    held: false,
    note:
        'DONE: full diene_config typed-loader adoption. The local '
        'AppConfigLoader seam is deleted; loadAppConfig/loadAppConfigResult '
        'compose the published ConfigLoader/ConfigBlock/ConfigSchema directly '
        'and every consumer (main and config_test) calls those functions. Only '
        "the app's own typed AppConfig model — which diene_config cannot "
        'provide — remains app-owned.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/auth/*_auth_gateway.dart + session_controller.dart',
    dienePackage: 'diene_auth_engine 1.0.2 (pub.dev)',
    held: false,
    note:
        'DONE: the local AuthGateway and ExtraParamsSignIn seams are deleted. '
        'SessionController and DeferredLoginReceiver drive the published '
        "diene_auth_engine AuthProvider directly (signIn's extraParams "
        'signature included); the demo and Logto providers implement / '
        'construct the published AuthProvider, so no compatibility facade '
        'remains in the auth transport.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/generated/service/** (retrofit fallback client)',
    dienePackage: 'diene_api_engine 1.0.0 (pub.dev)',
    held: false,
    note:
        'CONTRACT-ALIGNED: callers speak the published Result/Problem contract '
        'diene_api_engine returns. FOLLOW-ON OWED, NOT DONE: swapping the '
        'generated retrofit fallback client (lib/generated/service/**) for the '
        'diene_api_engine surface is separate work with its own ownership, '
        'recorded on the node for assignment.',
  ),
  E4IntegrationPoint(
    localBridge: 'lib/integration/observability_wiring.dart',
    dienePackage: 'observability payload LPSM standard (state: done)',
    held: false,
    note:
        'STANDS LIVE: LPSM labels projected from AppIdentityConfig; concrete '
        'OTel/Faro exporter transport lands with its own work (see SignalSink).',
  ),
];

/// True when every point has been cleared — i.e. the published diene surface is
/// integrated and this node holds nothing pending. Transport follow-ons named
/// in the points' notes are tracked on the node, not by this flag.
bool get e4IntegrationComplete =>
    e4IntegrationMap.every((E4IntegrationPoint p) => !p.held);

/// The held points, if any. All are cleared: the published diene packages
/// landed via pub.dev, dissolving the original `lib/dart/e2e` await.
List<E4IntegrationPoint> get e4HeldPoints =>
    e4IntegrationMap.where((E4IntegrationPoint p) => p.held).toList();
