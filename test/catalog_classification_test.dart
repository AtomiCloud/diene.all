import 'package:diene_flutter_base/core/problem_catalog.dart';
import 'package:diene_flutter_base/core/result.dart';
import 'package:diene_flutter_base/problems/catalog_classification.dart';
import 'package:diene_flutter_base/problems/problem_registry.dart';
import 'package:flutter_test/flutter_test.dart';

const String _endpoint = '/user/me';
const String _rateLimited = 'urn:test:rate-limited';
const String _revoked = 'urn:test:session-revoked';
const String _upstreamDown = 'urn:test:upstream-down';

const Map<String, Map<int, ProblemCatalogEntry>> _catalogRows =
    <String, Map<int, ProblemCatalogEntry>>{
      _endpoint: <int, ProblemCatalogEntry>{
        429: ProblemCatalogEntry(
          type: _rateLimited,
          title: 'Too many requests',
          status: 429,
          recoverable: true,
        ),
        401: ProblemCatalogEntry(
          type: _revoked,
          title: 'Session revoked',
          status: 401,
          recoverable: false,
        ),
        502: ProblemCatalogEntry(
          type: _upstreamDown,
          title: 'Upstream unavailable',
          status: 502,
          recoverable: false,
        ),
      },
    };

const Map<String, ProblemErrorInfo> _registryEntries =
    <String, ProblemErrorInfo>{
      _rateLimited: ProblemErrorInfo(
        tier: ProblemTier.recoverable,
        headline: 'Too many requests',
        guidance: 'Wait a moment, then try again.',
        retryable: true,
      ),
      _revoked: ProblemErrorInfo(
        tier: ProblemTier.fatal,
        headline: 'Signed out',
        guidance: 'Sign in again to continue.',
        retryable: false,
      ),
      _upstreamDown: ProblemErrorInfo(
        tier: ProblemTier.fatal,
        headline: 'Service unavailable',
        guidance: 'Please try again later.',
        retryable: false,
      ),
    };

/// Builds a classifier, optionally with tampered registry entries so the
/// invariant can be shown to actually fire.
({CatalogErrorClassifier classifier, List<Problem> uncatalogued, List<Problem> unregistered})
_build({Map<String, ProblemErrorInfo> overrides = const <String, ProblemErrorInfo>{}}) {
  final List<Problem> uncatalogued = <Problem>[];
  final List<Problem> unregistered = <Problem>[];
  return (
    classifier: CatalogErrorClassifier(
      catalog: ProblemCatalog(
        endpoints: _catalogRows,
        onUnexpected: (Problem problem) async => uncatalogued.add(problem),
      ),
      registry: ProblemRegistry(
        entries: <String, ProblemErrorInfo>{..._registryEntries, ...overrides},
        onUnregistered: unregistered.add,
      ),
    ),
    uncatalogued: uncatalogued,
    unregistered: unregistered,
  );
}

ClassifiedProblem _expectSuccess(Result<ClassifiedProblem> result) =>
    result.fold<ClassifiedProblem>(
      onSuccess: (ClassifiedProblem value) => value,
      onFailure: (Problem problem) =>
          fail('expected a consistent classification, got ${problem.detail}'),
    );

Problem _expectFailure(Result<ClassifiedProblem> result) =>
    result.fold<Problem>(
      onSuccess: (ClassifiedProblem value) =>
          fail('expected an inconsistency failure, got $value'),
      onFailure: (Problem problem) => problem,
    );

void main() {
  group('catalog error classification', () {
    test('a catalogued recoverable response classifies as recoverable',
        () async {
      final harness = _build();
      final ClassifiedProblem classified = _expectSuccess(
        await harness.classifier.classify(
          endpoint: _endpoint,
          status: 429,
          detail: 'slow down',
        ),
      );

      expect(classified.problem.type, _rateLimited);
      expect(classified.problem.status, 429);
      expect(classified.problem.detail, 'slow down');
      expect(classified.info.tier, ProblemTier.recoverable);
      expect(classified.isFatal, isFalse);
      expect(classified.retryable, isTrue);
      expect(classified.uncatalogued, isFalse);
      expect(classified.feedsCatalogLoop, isFalse);
      expect(classified.isConsistent, isTrue);
      expect(harness.uncatalogued, isEmpty);
      expect(harness.unregistered, isEmpty);
    });

    test('a catalogued fatal response classifies as fatal', () async {
      final harness = _build();
      final ClassifiedProblem classified = _expectSuccess(
        await harness.classifier.classify(endpoint: _endpoint, status: 401),
      );

      expect(classified.problem.type, _revoked);
      expect(classified.info.tier, ProblemTier.fatal);
      expect(classified.isFatal, isTrue);
      expect(classified.retryable, isFalse);
      expect(classified.info.headline, 'Signed out');
      expect(classified.uncatalogued, isFalse);
    });

    test('a catalogued 5xx stays fatal and non-retryable', () async {
      final harness = _build();
      final ClassifiedProblem classified = _expectSuccess(
        await harness.classifier.classify(endpoint: _endpoint, status: 502),
      );

      expect(classified.problem.status, 502);
      expect(classified.isFatal, isTrue);
      expect(classified.retryable, isFalse);
    });

    test('an UNCATALOGUED status behaves as a fatal 5xx and feeds the loop',
        () async {
      final harness = _build();
      final ClassifiedProblem classified = _expectSuccess(
        await harness.classifier.classify(
          endpoint: _endpoint,
          status: 418,
          detail: 'teapot',
        ),
      );

      expect(classified.problem.type, uncataloguedProblemType);
      expect(classified.problem.status, 500, reason: 'uncatalogued = 5xx');
      expect(classified.upstreamStatus, 418);
      expect(classified.problem.data['upstreamStatus'], 418);
      expect(classified.problem.data['endpoint'], _endpoint);
      expect(classified.uncatalogued, isTrue);
      expect(classified.isFatal, isTrue);
      expect(classified.retryable, isFalse);
      expect(classified.info.registered, isFalse);
      expect(classified.feedsCatalogLoop, isTrue);
      expect(
        harness.uncatalogued.map((Problem problem) => problem.status),
        <int>[500],
        reason: 'the catalog loop sink must be notified exactly once',
      );
    });

    test('an UNCATALOGUED endpoint behaves the same as an unknown status',
        () async {
      final harness = _build();
      final ClassifiedProblem classified = _expectSuccess(
        await harness.classifier.classify(
          endpoint: '/never/catalogued',
          status: 404,
        ),
      );

      expect(classified.problem.type, uncataloguedProblemType);
      expect(classified.problem.status, 500);
      expect(classified.isFatal, isTrue);
      expect(classified.feedsCatalogLoop, isTrue);
      expect(harness.uncatalogued.length, 1);
    });

    test(
      'a registry entry cannot soften an uncatalogued response into a banner',
      () async {
        // Someone registers the uncatalogued URN as a friendly retry banner.
        final harness = _build(
          overrides: const <String, ProblemErrorInfo>{
            uncataloguedProblemType: ProblemErrorInfo(
              tier: ProblemTier.recoverable,
              headline: 'Hiccup',
              guidance: 'Just try again.',
              retryable: true,
            ),
          },
        );
        final ClassifiedProblem classified = _expectSuccess(
          await harness.classifier.classify(endpoint: _endpoint, status: 418),
        );

        expect(
          classified.isFatal,
          isTrue,
          reason: 'uncatalogued is forced through the fallback contract',
        );
        expect(classified.retryable, isFalse);
        expect(classified.info.registered, isFalse);
      },
    );

    test(
      'rendering a 5xx problem as recoverable is REFUSED by the invariant',
      () async {
        // The sabotage the goal names: a recoverable presentation over a 5xx.
        final harness = _build(
          overrides: const <String, ProblemErrorInfo>{
            _upstreamDown: ProblemErrorInfo(
              tier: ProblemTier.recoverable,
              headline: 'Blip',
              guidance: 'Tap retry.',
              retryable: true,
            ),
          },
        );
        final Problem problem = _expectFailure(
          await harness.classifier.classify(endpoint: _endpoint, status: 502),
        );

        expect(problem.type, classifierInconsistencyType);
        expect(problem.status, 500);
        expect(problem.data['problemType'], _upstreamDown);
        expect(problem.data['problemStatus'], 502);
        expect(problem.data['tier'], 'recoverable');
        expect(problem.data['retryable'], isTrue);
        expect(problem.data['upstreamStatus'], 502);
      },
    );

    test('the invariant accepts every well-formed pairing', () {
      const ClassifiedProblem recoverable4xx = ClassifiedProblem(
        problem: Problem(type: _rateLimited, title: 'x', status: 429),
        info: ProblemErrorInfo(
          tier: ProblemTier.recoverable,
          headline: 'x',
          guidance: 'x',
          retryable: true,
        ),
        endpoint: _endpoint,
        upstreamStatus: 429,
      );
      const ClassifiedProblem fatal5xx = ClassifiedProblem(
        problem: Problem(type: _upstreamDown, title: 'x', status: 502),
        info: ProblemErrorInfo(
          tier: ProblemTier.fatal,
          headline: 'x',
          guidance: 'x',
          retryable: false,
        ),
        endpoint: _endpoint,
        upstreamStatus: 502,
      );

      expect(recoverable4xx.isConsistent, isTrue);
      expect(fatal5xx.isConsistent, isTrue);
    });

    test('the invariant rejects an uncatalogued problem shown as non-fatal', () {
      const ClassifiedProblem tampered = ClassifiedProblem(
        problem: Problem(
          type: uncataloguedProblemType,
          title: 'x',
          status: 500,
        ),
        info: ProblemErrorInfo(
          tier: ProblemTier.recoverable,
          headline: 'x',
          guidance: 'x',
          retryable: false,
        ),
        endpoint: _endpoint,
        upstreamStatus: 418,
      );

      expect(tampered.isConsistent, isFalse);
    });
  });
}
