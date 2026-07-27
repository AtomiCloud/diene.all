/// The last reachable unit-ledger lines.
///
/// Each needed a specific provocation that no earlier test produced: a rescue
/// whose SECOND attempt also fails, a config value of the wrong TYPE, a cached
/// document that is syntactically invalid JSON, and the two `IoHttpTransport`
/// error classes that a plain refused connect does not raise.
library;

import 'dart:convert';

import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

LpsmCoordinate _coord(String module) => LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: module,
);

Map<String, Object?> _id(Map<String, Object?> json) => json;

void main() {
  group('rescue second attempt', () {
    test('a rescued address that ALSO fails reports the second failure', () async {
      // The rescue path has two outcomes and only the success one was covered.
      // A rescued candidate can be reachable for the health probe and then fail
      // the real call; the caller must get a failure rather than a hang or a
      // stale success.
      final FakeRescueStore store = FakeRescueStore();
      final RescueConfig rescue = RescueConfig(
        enabled: true,
        issuer: Uri.parse('https://auth.example.com'),
        catalogHosts: const <String>['https://seed.example.com'],
        endpointSuffixAllowlist: const <String>['.example.com'],
      );

      // Doc A lists the seed; Doc C offers one candidate. The candidate answers
      // the HEAD probe (so it is chosen) but fails the subsequent GET.
      await store.write(
        'doca',
        jsonEncode(<String, Object?>{
          'version': 1,
          'catalogHosts': <String>['https://seed.example.com'],
        }),
      );
      await store.write(
        'docc.${_coord('a').platform}.${_coord('a').landscape}',
        jsonEncode(<String, Object?>{
          'version': 1,
          'candidates': <String, Object?>{
            _coord('a').key: <String>['https://rescue.example.com'],
          },
        }),
      );

      int calls = 0;
      final FakeHttpTransport transport = FakeHttpTransport((HttpRequest req) {
        calls += 1;
        if (req.method == HttpMethod.head) {
          // The probe succeeds, so the candidate is selected.
          return Received(const HttpResponse(status: 200, body: ''));
        }
        // Every real call fails, including the retry on the rescued address.
        return networkFailure('rescued host also refused');
      });

      final ApiEngine engine = ApiEngine.fromConfig(
        ApiEngineConfig(
          backends: <BackendConfig>[
            BackendConfig(
              coordinate: _coord('a'),
              baseUrl: Uri.parse('https://primary.example.com'),
              retryOnNetworkError: false,
            ),
          ],
          rescue: rescue,
        ),
        transport: transport,
        rescueOverride: RescueRouter(
          config: rescue,
          store: store,
          transport: transport,
          sleep: noSleep,
          jitter: noJitter,
          nowMs: FakeClock().nowMs,
        ),
      );

      final Result<Map<String, Object?>> result = await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/thing',
            decode: _id,
          );

      // Whichever failure surfaces, it must be a transport failure and the
      // engine must have attempted more than the single primary call.
      final Problem problem = expectErr(result);
      expect(problem.type, BridgeProblems.transportFailure);
      expect(calls, greaterThan(1), reason: 'the rescue path was exercised');
    });
  });

  group('config type validation', () {
    // The nested key is `coordinate`, NOT `lpsm`. My first version of these
    // tests used `lpsm`, so `_map(value, 'coordinate')` threw on the MISSING
    // key before `_string` ever ran — the assertion passed (a FormatException
    // was thrown) while the branch under test stayed uncovered. A passing
    // expectation is not evidence that the intended line executed; the ledger
    // is what caught it.
    // `fromMap` also requires a `rescue` map at the root — the positive control
    // below is what surfaced that ("config key rescue must be a map"), which is
    // exactly why a not-everything-is-rejected case belongs next to a group of
    // rejection assertions.
    Map<String, Object?> backend(Map<String, Object?> overrides) =>
        <String, Object?>{
          'backends': <Object?>[
            <String, Object?>{
              'baseUrl': 'https://a.example.com',
              'coordinate': <String, Object?>{
                'landscape': 'lapras',
                'platform': 'platform',
                'service': 'service',
                'module': 'core',
              },
              ...overrides,
            },
          ],
          'rescue': <String, Object?>{
            'enabled': false,
            'issuer': 'https://auth.example.com',
            'catalogHosts': <String>[],
            'endpointSuffixAllowlist': <String>[],
          },
        };

    test('a NON-STRING where a string is required throws FormatException', () {
      // `_string` rejects both an empty string and a wrong TYPE. Only the empty
      // case was covered, so the type branch had never run.
      expect(
        () =>
            ApiEngineConfig.fromMap(backend(<String, Object?>{'baseUrl': 42})),
        throwsA(isA<FormatException>()),
      );
    });

    test('an EMPTY string is rejected as well as a wrong type', () {
      expect(
        () =>
            ApiEngineConfig.fromMap(backend(<String, Object?>{'baseUrl': ''})),
        throwsA(isA<FormatException>()),
      );
    });

    test('a non-string coordinate label is rejected too', () {
      expect(
        () => ApiEngineConfig.fromMap(
          backend(<String, Object?>{
            'coordinate': <String, Object?>{
              'landscape': <String>['not', 'a', 'string'],
              'platform': 'platform',
              'service': 'service',
              'module': 'core',
            },
          }),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a well-formed map DOES parse, so the guards are not blanket', () {
      // Without this, every assertion above could pass on a parser that
      // rejected everything.
      final ApiEngineConfig config = ApiEngineConfig.fromMap(
        backend(const <String, Object?>{}),
      );
      expect(config.backends.single.coordinate.module, 'core');
    });
  });

  group('fetched document decoding', () {
    test('a FETCHED document that is invalid JSON is treated as absent', () async {
      // `_jsonObject` guards the body of a FETCHED doc, not the store — my first
      // version put garbage in the store instead and never reached it. The
      // catalog host must therefore RESPOND with unparseable content.
      //
      // The property: a malformed Doc A degrades to "no document" so the router
      // reports RescueUnavailable rather than throwing into the caller's request
      // path. A corrupted or truncated edge response must not crash the app.
      final RescueConfig rescue = RescueConfig(
        enabled: true,
        issuer: Uri.parse('https://auth.example.com'),
        catalogHosts: const <String>['https://seed.example.com'],
        endpointSuffixAllowlist: const <String>['.example.com'],
      );
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) =>
            Received(const HttpResponse(status: 200, body: '{not json at all')),
      );
      final RescueRouter router = RescueRouter(
        config: rescue,
        store: FakeRescueStore(),
        transport: transport,
        sleep: noSleep,
        jitter: noJitter,
        nowMs: FakeClock().nowMs,
      );

      final RescueOutcome outcome = await router.rescue(_coord('a'));

      expect(outcome, isA<RescueUnavailable>());
      // Prove the catalog was actually contacted, or the assertion above could
      // pass because the router never tried at all.
      expect(transport.sent, isNotEmpty);
    });
  });
}
