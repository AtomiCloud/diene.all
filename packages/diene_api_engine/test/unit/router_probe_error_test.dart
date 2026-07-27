/// The rescue router CONTAINS a transport that violates the never-throw
/// contract.
///
/// HISTORY, kept because the red-to-green transition is the evidence. An earlier
/// version of this file pinned the OPPOSITE behaviour: three passing tests
/// asserting that a throwing transport propagated out of `rescue()` and
/// `probeHealthy()`. Those were deliberately claims about what the code DID, not
/// about what it should do, written while the design decision was unmade.
///
/// The hardening has since landed, so those pins are now WRONG and had to be
/// updated deliberately — which is exactly what a red-to-green target is for. The
/// assertions are inverted here rather than deleted, so the file records both the
/// defect and its fix.
library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// A transport that violates the documented never-throw contract.
class _ThrowingTransport implements HttpTransport {
  int calls = 0;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    calls += 1;
    throw StateError('transport contract violated');
  }
}

/// Throws only for the Doc-A seed host, so a later host can still answer.
class _PartiallyThrowingTransport implements HttpTransport {
  _PartiallyThrowingTransport(this._throwOnHost, this._responder);

  final String _throwOnHost;
  final TransportOutcome Function(HttpRequest request) _responder;
  final List<Uri> sent = <Uri>[];

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    sent.add(request.url);
    if (request.url.host == _throwOnHost) {
      throw StateError('this mirror is broken');
    }
    return _responder(request);
  }
}

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: module,
);

RescueConfig _rescue({List<String>? hosts}) => RescueConfig(
  enabled: true,
  issuer: Uri.parse('https://auth.example.com'),
  catalogHosts: hosts ?? const <String>['https://seed.example.com'],
  endpointSuffixAllowlist: const <String>['.example.com'],
);

RescueRouter _router(
  HttpTransport transport, {
  Map<String, String>? seed,
  List<String>? hosts,
}) => RescueRouter(
  config: _rescue(hosts: hosts),
  store: FakeRescueStore(seed),
  transport: transport,
  sleep: noSleep,
  jitter: noJitter,
  nowMs: FakeClock().nowMs,
);

void main() {
  group('a throwing transport is CONTAINED', () {
    test('probeHealthy fails closed instead of propagating', () async {
      // Previously asserted `throwsA(isA<StateError>())`. A probe that cannot
      // answer must read as NOT healthy — treating it as healthy would pin
      // traffic to a host nobody has verified.
      final bool healthy = await _router(
        _ThrowingTransport(),
      ).probeHealthy(Uri.parse('https://a.example.com'));

      expect(healthy, isFalse);
    });

    test('rescue() returns an outcome instead of crashing the caller', () async {
      // Previously asserted `throwsA(isA<StateError>())` from the Doc A fetch.
      // The caller of a rescue is mid-request; an unhandled error there is a
      // crash in an app, not a diagnosable failure.
      final _ThrowingTransport transport = _ThrowingTransport();

      final RescueOutcome outcome = await _router(
        transport,
      ).rescue(_coord('core'));

      expect(outcome, isA<RescueUnavailable>());
      expect((outcome as RescueUnavailable).reason, isNotEmpty);
      // Proves the fetch was actually attempted, so the pass is not vacuous.
      expect(transport.calls, greaterThan(0));
    });

    test(
      'a WELL-BEHAVED transport still works, so nothing was broken to fix it',
      () async {
        // The neighbouring case that already worked. Keeping it asserts the
        // hardening did not turn a real failure into a swallowed one.
        final RescueOutcome outcome = await _router(
          FakeHttpTransport((HttpRequest _) => networkFailure('down')),
        ).rescue(_coord('core'));

        expect(outcome, isA<RescueUnavailable>());
      },
    );
  });

  group('containment is scoped PER HOST, not per scan', () {
    test(
      'one throwing mirror does not abort a scan another seed can satisfy',
      () async {
        // The property that makes per-host scoping worth the extra code: a single
        // broken mirror must not deny a rescue the remaining seeds could serve.
        // `broken.example.com` throws; `good.example.com` answers with a Doc A.
        final _PartiallyThrowingTransport
        transport = _PartiallyThrowingTransport('broken.example.com', (
          HttpRequest r,
        ) {
          if (r.url.path == '/fleet.json') {
            return Received(
              const HttpResponse(
                status: 200,
                body: '{"version":1,"catalogHosts":["good.example.com"]}',
              ),
            );
          }
          // No Doc C, so the scan ends in RescueUnavailable — the point here
          // is that the BROKEN host did not stop it from getting this far.
          return Received(const HttpResponse(status: 404, body: ''));
        });

        final RescueOutcome outcome = await _router(
          transport,
          hosts: <String>[
            'https://broken.example.com',
            'https://good.example.com',
          ],
        ).rescue(_coord('core'));

        expect(outcome, isA<RescueUnavailable>());
        // Decisive: the scan reached the SECOND host after the first threw.
        expect(
          transport.sent.map((Uri u) => u.host),
          containsAllInOrder(<String>[
            'broken.example.com',
            'good.example.com',
          ]),
        );
      },
    );
  });
}
