import 'package:diene_flutter_base/problems/problem_registry.dart';
import 'package:diene_problems/diene_problems.dart' hide ProblemRegistry;
import 'package:flutter_test/flutter_test.dart';

const String _notOnboarded = 'urn:test:not-onboarded';
const String _rateLimited = 'urn:test:rate-limited';
const String _revoked = 'urn:test:session-revoked';

const Map<String, ProblemErrorInfo> _entries = <String, ProblemErrorInfo>{
  _notOnboarded: ProblemErrorInfo(
    tier: ProblemTier.recoverable,
    headline: 'Finish setting up',
    guidance: 'Complete onboarding to continue.',
    retryable: false,
  ),
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
};

Problem _problem(
  String type, {
  int status = 400,
  bool recoverable = false,
}) => Problem(
  type: type,
  title: 'Upstream said $status',
  status: status,
  recoverable: recoverable,
);

void main() {
  group('problem registry / error-info mapping', () {
    test('a registered recoverable type maps to its exact entry', () {
      final ProblemRegistry registry = ProblemRegistry(entries: _entries);
      final ProblemErrorInfo info = registry.resolve(
        _problem(_rateLimited, status: 429, recoverable: true),
      );

      expect(info.tier, ProblemTier.recoverable);
      expect(info.headline, 'Too many requests');
      expect(info.guidance, 'Wait a moment, then try again.');
      expect(info.retryable, isTrue);
      expect(info.isFatal, isFalse);
      expect(info.registered, isTrue);
    });

    test('a registered fatal type maps to the blocking tier', () {
      final ProblemRegistry registry = ProblemRegistry(entries: _entries);
      final ProblemErrorInfo info = registry.resolve(
        _problem(_revoked, status: 401),
      );

      expect(info.tier, ProblemTier.fatal);
      expect(info.isFatal, isTrue);
      expect(info.headline, 'Signed out');
      expect(info.retryable, isFalse);
    });

    test('recoverable does not imply retryable', () {
      final ProblemRegistry registry = ProblemRegistry(entries: _entries);
      final ProblemErrorInfo info = registry.resolve(
        _problem(_notOnboarded, status: 404),
      );

      expect(info.tier, ProblemTier.recoverable);
      expect(
        info.retryable,
        isFalse,
        reason: 'onboarding is fixed by acting, not by retrying',
      );
    });

    test('every registered type resolves to a registered info', () {
      final ProblemRegistry registry = ProblemRegistry(entries: _entries);

      expect(registry.registeredTypes.toSet(), _entries.keys.toSet());
      for (final String type in _entries.keys) {
        expect(registry.isRegistered(type), isTrue, reason: type);
        expect(registry.resolve(_problem(type)).registered, isTrue,
            reason: type);
        expect(
          registry.resolve(_problem(type)).headline,
          _entries[type]!.headline,
          reason: 'mapping for $type must not drift',
        );
      }
    });

    test('an unregistered type falls back and is flagged unregistered', () {
      final List<Problem> misses = <Problem>[];
      final ProblemRegistry registry = ProblemRegistry(
        entries: _entries,
        onUnregistered: misses.add,
      );
      final ProblemErrorInfo info = registry.resolve(
        _problem('urn:test:brand-new', status: 418, recoverable: true),
      );

      expect(info.registered, isFalse);
      expect(info.tier, ProblemTier.recoverable);
      expect(info.retryable, isTrue);
      expect(misses.map((Problem problem) => problem.type), <String>[
        'urn:test:brand-new',
      ]);
    });

    test('an unregistered 5xx falls back to fatal even if marked recoverable',
        () {
      final ProblemRegistry registry = ProblemRegistry(entries: _entries);
      final ProblemErrorInfo info = registry.resolve(
        _problem('urn:test:unknown-5xx', status: 503, recoverable: true),
      );

      expect(info.tier, ProblemTier.fatal);
      expect(info.retryable, isFalse);
      expect(info.registered, isFalse);
    });

    test('an unregistered non-recoverable 4xx falls back to fatal', () {
      final ProblemRegistry registry = ProblemRegistry(entries: _entries);
      final ProblemErrorInfo info = registry.resolve(
        _problem('urn:test:unknown-4xx', status: 409),
      );

      expect(info.tier, ProblemTier.fatal);
      expect(info.headline, 'Upstream said 409');
    });

    test('the miss sink fires only for misses, never for hits', () {
      final List<Problem> misses = <Problem>[];
      final ProblemRegistry registry = ProblemRegistry(
        entries: _entries,
        onUnregistered: misses.add,
      );

      registry.resolve(_problem(_revoked));
      registry.resolve(_problem(_rateLimited));
      expect(misses, isEmpty);

      registry.resolve(_problem('urn:test:missing'));
      expect(misses.length, 1);
    });

    test('extendedWith layers over the base without mutating it', () {
      final ProblemRegistry base = ProblemRegistry(entries: _entries);
      final ProblemRegistry extended = base.extendedWith(
        const <String, ProblemErrorInfo>{
          'urn:test:feature': ProblemErrorInfo(
            tier: ProblemTier.fatal,
            headline: 'Feature unavailable',
            guidance: 'Try again later.',
            retryable: false,
          ),
        },
      );

      expect(extended.isRegistered('urn:test:feature'), isTrue);
      expect(extended.isRegistered(_revoked), isTrue);
      expect(
        base.isRegistered('urn:test:feature'),
        isFalse,
        reason: 'the base registry must not be mutated',
      );
      expect(
        extended.resolve(_problem('urn:test:feature')).headline,
        'Feature unavailable',
      );
    });

    test('asUnregistered preserves the contract but clears the flag', () {
      final ProblemErrorInfo info = _entries[_rateLimited]!.asUnregistered();

      expect(info.registered, isFalse);
      expect(info.tier, ProblemTier.recoverable);
      expect(info.headline, 'Too many requests');
      expect(info.retryable, isTrue);
    });
  });
}
