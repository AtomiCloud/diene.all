/// The rescue router's behaviour when a transport VIOLATES the never-throw
/// contract.
///
/// FINDING, recorded as a test rather than as prose. `HttpTransport` is a public
/// seam, so a third-party implementation that throws is a real possibility. The
/// router guards ONE place — `_jsonObject`, for a malformed document body — and
/// carries an `onError` arm in `_probeWithinBudget`, but the DOC FETCHES
/// themselves are unguarded. Measured: a throwing transport escapes from
/// `_fetchDocA` (router.dart:252) as `Bad state: transport contract violated`,
/// before the probe stage is ever reached.
///
/// So today the throw propagates out of `rescue()` into the caller's request
/// path. That is a robustness gap in the component whose entire purpose is to
/// degrade gracefully during an outage: a misbehaving transport turns a rescue
/// attempt into an unhandled crash instead of a `Problem` the caller can act on.
///
/// This test PINS TODAY'S ACTUAL BEHAVIOUR so the gap is visible and any future
/// hardening has a red-to-green target. It deliberately does NOT assert the
/// behaviour I would prefer — that would be a failing test asserting a fix that
/// does not exist. The gap is reported upward instead; hardening the router's
/// fetch paths is a product change beyond closing a coverage ledger, and inventing
/// it unilaterally at proof time is how a "small fix" reopens a certified proof.
library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// A transport that violates the documented never-throw contract.
class _ThrowingTransport implements HttpTransport {
  @override
  Future<TransportOutcome> send(HttpRequest request) async =>
      throw StateError('transport contract violated');
}

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: module,
);

RescueRouter _router(HttpTransport transport, {Map<String, String>? seed}) =>
    RescueRouter(
      config: RescueConfig(
        enabled: true,
        issuer: Uri.parse('https://auth.example.com'),
        catalogHosts: const <String>['https://seed.example.com'],
        endpointSuffixAllowlist: const <String>['.example.com'],
      ),
      store: FakeRescueStore(seed),
      transport: transport,
      sleep: noSleep,
      jitter: noJitter,
      nowMs: FakeClock().nowMs,
    );

void main() {
  group('a throwing transport is NOT contained by the router today', () {
    test('probeHealthy propagates rather than failing closed', () async {
      // Documents why `_probeWithinBudget` needs its `onError` arm at all: this
      // future really can reject.
      await expectLater(
        _router(
          _ThrowingTransport(),
        ).probeHealthy(Uri.parse('https://a.example.com')),
        throwsA(isA<StateError>()),
      );
    });

    test('rescue() propagates from the Doc A fetch, before any probe', () async {
      // The escape point is `_fetchDocA`, not the probe. Pinned so that if the
      // fetch paths are ever guarded, THIS test goes red and has to be updated
      // deliberately — rather than the improvement passing unnoticed.
      await expectLater(
        _router(_ThrowingTransport()).rescue(_coord('core')),
        throwsA(isA<StateError>()),
      );
    });

    test('a WELL-BEHAVED transport is contained, so the gap is specific', () async {
      // The contrast that makes the finding meaningful: a transport returning a
      // NetworkFailure (the documented way to report a hard failure) is handled
      // and yields an outcome. The gap is about THROWING, not about failure.
      final RescueOutcome outcome = await _router(
        FakeHttpTransport((HttpRequest _) => networkFailure('down')),
      ).rescue(_coord('core'));

      expect(outcome, isA<RescueUnavailable>());
    });
  });
}
