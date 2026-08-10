/// Containment of a transport that violates the never-throw contract, and WHERE
/// that containment lives.
///
/// `HttpTransport` documents that it never throws — a hard failure is returned as
/// `NetworkFailure`. It is a PUBLIC seam of this package, so a third-party
/// implementation that violates the contract is a real possibility, and the
/// router must degrade rather than crash a caller mid-request.
///
/// CONTAINMENT IS AT ONE POINT PER PATH:
///   * document fetches  -> `_sendOrNull`, scoped per host
///   * candidate probes   -> `_probeWithinBudget`'s `onError` arm
///
/// `probeHealthy` deliberately does NOT catch. An earlier revision caught there
/// too, and that second containment point made the `onError` arm unreachable — a
/// handler that could never run. So this file asserts BOTH that a probe's future
/// rejects AND that the rejection is contained one level up.
library;

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Violates the contract on every call.
class _ThrowingTransport implements HttpTransport {
  int calls = 0;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    calls += 1;
    throw StateError('transport contract violated');
  }
}

/// Violates the contract on the PROBE only, so the document fetches succeed and
/// the scan actually reaches the probe stage.
class _ProbeThrowingTransport implements HttpTransport {
  int heads = 0;

  @override
  Future<TransportOutcome> send(HttpRequest request) async {
    if (request.method == HttpMethod.head) {
      heads += 1;
      throw StateError('probe transport threw');
    }
    if (request.url.path == '/fleet.json') {
      return Received(
        const HttpResponse(
          status: 200,
          body: '{"version":1,"catalogHosts":["seed.example.com"]}',
        ),
      );
    }
    return Received(
      const HttpResponse(
        status: 200,
        body:
            '{"version":1,"candidates":'
            '{"lapras.platform.service.core":["https://r.example.com"]}}',
      ),
    );
  }
}

/// Throws for one host only, so a later host can still answer.
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

const LpsmCoordinate _core = LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: 'core',
);

RescueRouter _router(HttpTransport transport, {List<String>? hosts}) =>
    RescueRouter(
      config: RescueConfig(
        enabled: true,
        issuer: Uri.parse('https://auth.example.com'),
        catalogHosts: hosts ?? const <String>['https://seed.example.com'],
        endpointSuffixAllowlist: const <String>['.example.com'],
      ),
      store: FakeRescueStore(),
      transport: transport,
      sleep: noSleep,
      jitter: noJitter,
      nowMs: FakeClock().nowMs,
    );

void main() {
  group('containment lives at ONE point per path', () {
    test('probeHealthy REJECTS — it does not contain, by design', () async {
      // If this ever starts resolving instead of throwing, someone has added a
      // second containment point and made the onError arm dead again.
      await expectLater(
        _router(
          _ThrowingTransport(),
        ).probeHealthy(Uri.parse('https://a.example.com')),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'a throwing PROBE is contained by the onError arm, not propagated',
      () async {
        // The scan reaches the probe stage (documents fetch fine), every probe
        // throws, and the caller still gets an outcome rather than an error.
        final _ProbeThrowingTransport transport = _ProbeThrowingTransport();

        final RescueOutcome outcome = await _router(transport).rescue(_core);

        expect(outcome, isA<RescueUnavailable>());
        // Non-vacuous: the probe stage was actually exercised.
        expect(transport.heads, greaterThan(0));
      },
    );

    test('a throwing FETCH is contained by _sendOrNull', () async {
      final _ThrowingTransport transport = _ThrowingTransport();

      final RescueOutcome outcome = await _router(transport).rescue(_core);

      expect(outcome, isA<RescueUnavailable>());
      expect((outcome as RescueUnavailable).reason, isNotEmpty);
      expect(transport.calls, greaterThan(0));
    });

    test(
      'a WELL-BEHAVED transport still works, so nothing was broken to fix it',
      () async {
        final RescueOutcome outcome = await _router(
          FakeHttpTransport((HttpRequest _) => networkFailure('down')),
        ).rescue(_core);

        expect(outcome, isA<RescueUnavailable>());
      },
    );
  });

  group('fetch containment is scoped PER HOST, not per scan', () {
    test(
      'one throwing mirror does not abort a scan another seed can satisfy',
      () async {
        final _PartiallyThrowingTransport transport =
            _PartiallyThrowingTransport('broken.example.com', (HttpRequest r) {
              if (r.url.path == '/fleet.json') {
                return Received(
                  const HttpResponse(
                    status: 200,
                    body: '{"version":1,"catalogHosts":["good.example.com"]}',
                  ),
                );
              }
              return Received(const HttpResponse(status: 404, body: ''));
            });

        final RescueOutcome outcome = await _router(
          transport,
          hosts: <String>[
            'https://broken.example.com',
            'https://good.example.com',
          ],
        ).rescue(_core);

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
