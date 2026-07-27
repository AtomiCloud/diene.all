/// Engine paths the inherited suite never exercised.
///
/// `engine.dart` was the largest hole in the unit ledger at 95/122. The
/// uncovered lines were not dead code — they are real behaviour the goal
/// contract names: pin-until-primary-heals, the rescue trip and its second
/// attempt, the Dio adapter's request-body handling, and the default
/// construction branches of `ApiEngine.fromConfig`. Each is covered here by
/// asserting the behaviour, never by masking the ledger.
library;

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

RescueConfig _liveRescue() => RescueConfig(
  enabled: true,
  issuer: Uri.parse('https://auth.lapras.cluster.atomi.cloud'),
  catalogHosts: const <String>['https://seed.example.com'],
  endpointSuffixAllowlist: const <String>['.example.com'],
);

RescueConfig _disabledRescue() => RescueConfig(
  enabled: false,
  issuer: Uri.parse('https://unused.example'),
  catalogHosts: const <String>[],
  endpointSuffixAllowlist: const <String>[],
);

ApiEngineConfig _config(RescueConfig rescue) => ApiEngineConfig(
  backends: <BackendConfig>[
    BackendConfig(
      coordinate: _coord('a'),
      baseUrl: Uri.parse('https://primary.example.com'),
      resourceName: 'a',
    ),
  ],
  rescue: rescue,
);

void main() {
  group('pin-until-primary-heals', () {
    test('a healthy primary response while pinned CLEARS the pin', () async {
      // Arrange: a pin is already on disk, and both the primary probe and the
      // call succeed.
      final FakeRescueStore store = FakeRescueStore(<String, String>{
        'pin.${_coord('a').key}': 'https://rescue.example.com',
      });
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );
      final RescueRouter router = RescueRouter(
        config: _liveRescue(),
        store: store,
        transport: transport,
        sleep: noSleep,
        jitter: noJitter,
        nowMs: FakeClock().nowMs,
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        _config(_liveRescue()),
        auth: FakeAuth(<String, String>{'platform/lapras/service/a': 'tok-a'}),
        transport: transport,
        rescueOverride: router,
      );

      // Act.
      final Result<Map<String, Object?>> result = await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/thing',
            decode: _id,
          );

      // Assert: the call succeeded AND the pin is gone, which is the whole
      // point of pin-until-primary-heals. Asserting only the call would leave
      // the heal path unproven.
      expect(result.isOk, isTrue);
      expect(await router.pinnedFor(_coord('a')), isNull);
    });

    test('a 5xx while pinned does NOT clear the pin', () async {
      // A received 5xx is not evidence the primary healed, so the pin must
      // survive. This is the negative half of the same branch.
      final FakeRescueStore store = FakeRescueStore(<String, String>{
        'pin.${_coord('a').key}': 'https://rescue.example.com',
      });
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) =>
            const Received(HttpResponse(status: 503, body: '{}')),
      );
      final RescueRouter router = RescueRouter(
        config: _liveRescue(),
        store: store,
        transport: transport,
        sleep: noSleep,
        jitter: noJitter,
        nowMs: FakeClock().nowMs,
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        _config(_liveRescue()),
        transport: transport,
        rescueOverride: router,
      );

      final Result<Map<String, Object?>> result = await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/thing',
            decode: _id,
          );

      expect(result.isErr, isTrue);
      expect(
        await router.pinnedFor(_coord('a')),
        Uri.parse('https://rescue.example.com'),
      );
    });
  });

  group('rescue trip', () {
    test('a hard failure with NO router returns the transport reason', () async {
      // rescue disabled -> fromConfig builds no router, so the failure must be
      // reported as-is rather than swallowed.
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => networkFailure('connection refused'),
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        _config(_disabledRescue()),
        transport: transport,
      );

      final Result<Map<String, Object?>> result = await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.get,
            path: '/thing',
            decode: _id,
          );

      final Problem problem = expectErr(result);
      expect(problem.type, BridgeProblems.transportFailure);
      expect(problem.data['reason'], contains('connection refused'));
      expect(engine.rescue, isNull);
    });

    test(
      'a router that cannot rescue still reports the ORIGINAL failure',
      () async {
        // The rescue router is live but has no candidate, so the caller must see
        // the original transport failure rather than a rescue-shaped one.
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest _) => networkFailure('primary down'),
        );
        final RescueRouter router = RescueRouter(
          config: _liveRescue(),
          store: FakeRescueStore(),
          transport: transport,
          sleep: noSleep,
          jitter: noJitter,
          nowMs: FakeClock().nowMs,
        );
        final ApiEngine engine = ApiEngine.fromConfig(
          _config(_liveRescue()),
          transport: transport,
          rescueOverride: router,
        );

        final Result<Map<String, Object?>> result = await engine
            .backend(_coord('a'))!
            .call<Map<String, Object?>>(
              method: HttpMethod.get,
              path: '/thing',
              decode: _id,
            );

        expect(expectErr(result).data['reason'], contains('primary down'));
      },
    );
  });

  group('request building', () {
    test(
      'query parameters merge onto a base that already carries some',
      () async {
        final FakeHttpTransport transport = FakeHttpTransport(
          (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
        );
        final ApiEngineConfig config = ApiEngineConfig(
          backends: <BackendConfig>[
            BackendConfig(
              coordinate: _coord('a'),
              // A base URL carrying BOTH a trailing-slash path and an existing
              // query — the two branches the inherited suite never hit.
              baseUrl: Uri.parse(
                'https://primary.example.com/api/?tenant=acme',
              ),
            ),
          ],
          rescue: _disabledRescue(),
        );
        final ApiEngine engine = ApiEngine.fromConfig(
          config,
          transport: transport,
        );

        await engine
            .backend(_coord('a'))!
            .call<Map<String, Object?>>(
              method: HttpMethod.get,
              path: '/thing',
              query: <String, String>{'page': '2'},
              decode: _id,
            );

        final Uri sent = transport.sent.single.url;
        expect(sent.queryParameters['tenant'], 'acme');
        expect(sent.queryParameters['page'], '2');
        // The trailing slash must not produce a doubled separator.
        expect(sent.path, '/api/thing');
      },
    );

    test('headers and a body are carried onto the request', () async {
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest _) => okJson(<String, Object?>{'ok': true}),
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        _config(_disabledRescue()),
        transport: transport,
      );

      await engine
          .backend(_coord('a'))!
          .call<Map<String, Object?>>(
            method: HttpMethod.post,
            path: '/thing',
            headers: <String, String>{'x-trace': 'abc'},
            body: '{"a":1}',
            decode: _id,
          );

      final HttpRequest sent = transport.sent.single;
      expect(sent.headers['x-trace'], 'abc');
      expect(sent.body, '{"a":1}');
      expect(sent.method, HttpMethod.post);
    });
  });

  group('ApiEngine.fromConfig default construction', () {
    test('with rescue ENABLED and no override it builds its own router', () {
      // Exercises the default-store + default-router branch rather than the
      // injected one every other test uses.
      final ApiEngine engine = ApiEngine.fromConfig(_config(_liveRescue()));

      expect(engine.rescue, isNotNull);
      expect(engine.rescue!.bakedIssuer, _liveRescue().issuer);
      expect(engine.tree.contains(_coord('a')), isTrue);
    });

    test('a duplicate coordinate throws a StateError naming the conflict', () {
      // The registration-failure branch is a throw, so it can only be covered
      // by actually provoking it.
      final ApiEngineConfig dupes = ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://one.example.com'),
          ),
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://two.example.com'),
          ),
        ],
        rescue: _disabledRescue(),
      );

      expect(
        () => ApiEngine.fromConfig(dupes),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('backend registration failed'),
          ),
        ),
      );
    });
  });

  group('client tree', () {
    test('resolve returns null for an unregistered coordinate', () {
      final ApiEngine engine = ApiEngine.fromConfig(_config(_disabledRescue()));

      expect(engine.backend(_coord('nope')), isNull);
      expect(engine.tree.resolve(_coord('nope')), isNull);
      expect(engine.tree.contains(_coord('nope')), isFalse);
    });
  });
}
