/// Catalog-driven error classification port (argon feature port 4 of 5).
///
/// This is the sixth product-thoughtfulness deliverable from the goal doc:
/// "per-endpoint Problem catalog from the edge channel drives
/// recoverable-vs-fatal UX, uncatalogued = 5xx + feeds the catalog loop."
///
/// It composes the two halves:
/// * [ProblemCatalog] (the local runtime endpoint classifier defined below) —
///   endpoint + upstream status → [Problem];
/// * [ProblemRegistry] (`lib/problems/problem_registry.dart`) — [Problem] →
///   [ProblemErrorInfo] presentation contract;
///
/// and adds the three cases the gate must cover:
///
/// 1. **recoverable** — catalogued, non-5xx, marked recoverable → banner + retry;
/// 2. **fatal** — catalogued but not recoverable (or 5xx) → blocking tier;
/// 3. **uncatalogued** — no catalog row for that endpoint/status. The catalog
///    already synthesises a 500 `urn:diene:problem:uncatalogued` problem; this
///    classifier asserts the *consequence*: status 500, fatal tier, and
///    [ClassifiedProblem.uncatalogued] true so the case feeds the catalog loop
///    instead of being papered over.
///
/// The invariant that keeps this honest is [ClassifiedProblem.isConsistent]: a
/// problem whose status is 5xx may never carry a recoverable presentation. That
/// is what "render a recoverable Problem as fatal → red" tests against — the
/// classifier refuses to produce an inconsistent pairing, so tampering with
/// either side of the mapping shows up as a failed classification rather than a
/// merely different one.
///
/// The runtime endpoint classifier ([ProblemCatalog]) is a LOCAL type: the
/// published `diene_problems` `ProblemCatalog` is the CRD-EXPORT producer side
/// (`add`/`addType`/`toCrdContent`), not a runtime classifier, so it is hidden
/// on the import below. The per-row entry type is the published
/// [CatalogEntry] — its `typeUri` carries the URI a matched row classifies to.
library;

import 'package:diene_problems/diene_problems.dart' hide ProblemCatalog, ProblemRegistry;
import 'package:diene_result/diene_result.dart';

import 'problem_registry.dart';

/// The uncatalogued problem type URN synthesised by [ProblemCatalog.classify].
const String uncataloguedProblemType = 'urn:diene:problem:uncatalogued';

/// Notified once for each response the catalog had no row for.
typedef UnexpectedProblemSink = Future<void> Function(Problem problem);

/// Runtime endpoint classifier: maps `endpoint + upstream HTTP status` onto a
/// [Problem] using per-endpoint [CatalogEntry] rows.
///
/// This is the domain-side (transport → [Problem]) counterpart the frontend
/// classifier needs at runtime. It is deliberately NOT the published
/// `diene_problems` `ProblemCatalog`, which is the CRD-export producer side.
final class ProblemCatalog {
  ProblemCatalog({required this.endpoints, UnexpectedProblemSink? onUnexpected})
    : _onUnexpected = onUnexpected ?? _ignore;

  /// Per-endpoint, per-status catalog rows.
  final Map<String, Map<int, CatalogEntry>> endpoints;
  final UnexpectedProblemSink _onUnexpected;

  /// Classify an [endpoint] + upstream [status] into a [Problem].
  ///
  /// A catalogued row becomes the [Problem] its [CatalogEntry.typeUri] names; an
  /// uncatalogued endpoint/status synthesises a 500
  /// `urn:diene:problem:uncatalogued` problem and notifies the loop sink once.
  Future<Problem> classify({
    required String endpoint,
    required int status,
    String? detail,
    String? instance,
  }) async {
    final CatalogEntry? entry = endpoints[endpoint]?[status];
    if (entry != null) {
      return Problem(
        type: entry.typeUri,
        title: entry.title,
        status: entry.status,
        detail: detail,
        instance: instance,
        recoverable: entry.recoverable,
      );
    }
    final Problem unexpected = Problem(
      type: uncataloguedProblemType,
      title: 'Unexpected service response',
      status: 500,
      detail: detail,
      instance: instance,
      data: <String, Object?>{'endpoint': endpoint, 'upstreamStatus': status},
    );
    await _onUnexpected(unexpected);
    return unexpected;
  }

  static Future<void> _ignore(Problem problem) async {}
}

/// A [Problem] paired with the presentation contract it classified to.
final class ClassifiedProblem {
  const ClassifiedProblem({
    required this.problem,
    required this.info,
    required this.endpoint,
    required this.upstreamStatus,
  });

  final Problem problem;
  final ProblemErrorInfo info;

  /// The endpoint whose catalog was consulted.
  final String endpoint;

  /// The status actually returned by the service (which for an uncatalogued
  /// response differs from [Problem.status], since that becomes 500).
  final int upstreamStatus;

  /// Whether the catalog had no row for this endpoint/status pair.
  bool get uncatalogued => problem.type == uncataloguedProblemType;

  /// Whether the UI blocks the screen for this problem.
  bool get isFatal => info.isFatal;

  /// Whether a retry affordance is offered.
  bool get retryable => info.retryable;

  /// Whether this problem should feed the catalog-authoring loop.
  ///
  /// True when the catalog had no row, or when the registry had no entry for the
  /// type the catalog produced — both are gaps a human must close.
  bool get feedsCatalogLoop => uncatalogued || !info.registered;

  /// The classification invariant.
  ///
  /// A 5xx problem must never be presented as recoverable/retryable, and an
  /// uncatalogued problem must be a fatal 500. False means the catalog and the
  /// registry disagree.
  bool get isConsistent {
    if (problem.status >= 500 && (!info.isFatal || info.retryable)) {
      return false;
    }
    if (uncatalogued && (problem.status != 500 || !info.isFatal)) {
      return false;
    }
    return true;
  }

  @override
  String toString() =>
      'ClassifiedProblem($endpoint $upstreamStatus -> ${problem.type}, '
      'tier: ${info.tier.name}, uncatalogued: $uncatalogued)';
}

/// Problem type for a classifier that produced an inconsistent pairing.
const String classifierInconsistencyType =
    'urn:diene:problem:classification-inconsistent';

/// Classifies service responses into presentation contracts.
///
/// Stateless with both collaborators constructor-injected.
final class CatalogErrorClassifier {
  const CatalogErrorClassifier({
    required this.catalog,
    required this.registry,
  });

  final ProblemCatalog catalog;
  final ProblemRegistry registry;

  /// Classify a non-success response from [endpoint] with [status].
  ///
  /// Returns `Err` only when the catalog and the registry disagree (see
  /// [ClassifiedProblem.isConsistent]) — a wiring defect, not a service error.
  /// Every well-formed mapping, including the uncatalogued one, is an `Ok`
  /// carrying the [ClassifiedProblem].
  Future<Result<ClassifiedProblem>> classify({
    required String endpoint,
    required int status,
    String? detail,
    String? instance,
  }) async {
    final Problem problem = await catalog.classify(
      endpoint: endpoint,
      status: status,
      detail: detail,
      instance: instance,
    );
    final ProblemErrorInfo resolved = registry.resolve(problem);

    // Uncatalogued responses are forced through the fallback contract: a
    // registry entry must never be able to soften an unknown 5xx into a
    // recoverable banner.
    final ProblemErrorInfo info = problem.type == uncataloguedProblemType
        ? ProblemRegistry.fallbackFor(problem)
        : resolved;

    final ClassifiedProblem classified = ClassifiedProblem(
      problem: problem,
      info: info,
      endpoint: endpoint,
      upstreamStatus: status,
    );

    if (!classified.isConsistent) {
      return Err<ClassifiedProblem>(
        Problem(
          type: classifierInconsistencyType,
          title: 'Inconsistent problem classification',
          status: 500,
          detail:
              'Problem ${problem.type} (status ${problem.status}) classified as '
              'tier ${info.tier.name} (retryable: ${info.retryable}); a 5xx or '
              'uncatalogued problem must be fatal and non-retryable.',
          data: <String, Object?>{
            'endpoint': endpoint,
            'upstreamStatus': status,
            'problemType': problem.type,
            'problemStatus': problem.status,
            'tier': info.tier.name,
            'retryable': info.retryable,
          },
        ),
      );
    }
    return Ok<ClassifiedProblem>(classified);
  }
}
