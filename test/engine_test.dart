import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:test/test.dart';

LpsmCoordinate _coord(String module) => LpsmCoordinate(
      landscape: 'lapras',
      platform: 'platform',
      service: 'service',
      module: module,
    );

Map<String, Object?> _id(Map<String, Object?> json) => json;

RescueConfig _disabledRescue() => RescueConfig(
      enabled: false,
      issuer: Uri.parse('https://unused.example'),
      catalogHosts: const <String>[],
      endpointSuffixAllowlist: const <String>[],
    );

void main() {
  group('multi-backend', () {
    test('each backend carries its OWN per-resource token — no bleed',
        () async {
      // Arrange: two backends, each with its own resourceName (M slot).
      final ApiEngineConfig config = ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://a.example.com'),
            resourceName: 'a',
          ),
          BackendConfig(
            coordinate: _coord('b'),
            baseUrl: Uri.parse('https://b.example.com'),
            resourceName: 'b',
          ),
        ],
        rescue: _disabledRescue(),
      );
      final FakeHttpTransport transport = FakeHttpTransport.byHost(
        <String, TransportOutcome>{
          'a.example.com': okJson(<String, Object?>{'who': 'a'}),
          'b.example.com': okJson(<String, Object?>{'who': 'b'}),
        },
      );
      // Tokens keyed by ResourceKey.mapKey = platform/landscape/service/resource.
      final FakeAuth auth = FakeAuth(<String, String>{
        'platform/lapras/service/a': 'token-a',
        'platform/lapras/service/b': 'token-b',
      });
      final ApiEngine engine =
          ApiEngine.fromConfig(config, auth: auth, transport: transport);

      // Act
      final Result<Map<String, Object?>> a = await engine
          .backend(_coord('a'))!
          .call(method: HttpMethod.get, path: '/me', decode: _id);
      final Result<Map<String, Object?>> b = await engine
          .backend(_coord('b'))!
          .call(method: HttpMethod.get, path: '/me', decode: _id);

      // Assert
      expect(expectOk(a)['who'], 'a');
      expect(expectOk(b)['who'], 'b');
      expect(transport.sent[0].headers['Authorization'], 'Bearer token-a');
      expect(transport.sent[1].headers['Authorization'], 'Bearer token-b');
      // Each backend queried only its OWN resource key.
      expect(auth.queried, <String>[
        'platform/lapras/service/a',
        'platform/lapras/service/b',
      ]);
    });

    test('a token-resolution failure IS the call error (fail-closed)',
        () async {
      final ApiEngineConfig config = ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://a.example.com'),
            resourceName: 'a',
          ),
        ],
        rescue: _disabledRescue(),
      );
      final FakeHttpTransport transport = FakeHttpTransport.byHost(
        <String, TransportOutcome>{
          'a.example.com': okJson(<String, Object?>{'who': 'a'}),
        },
      );
      // No token for the key → FakeAuth returns Err.
      final ApiEngine engine = ApiEngine.fromConfig(
        config,
        auth: FakeAuth(<String, String>{}),
        transport: transport,
      );

      final Result<Map<String, Object?>> r = await engine
          .backend(_coord('a'))!
          .call(method: HttpMethod.get, path: '/me', decode: _id);

      expectErr(r);
      // The HTTP call was never attempted because the token failed.
      expect(transport.callCount, 0);
    });
  });

  group('rescue trip', () {
    test('hard failure trips the router, pins a rescued address, succeeds',
        () async {
      final LpsmCoordinate coord = _coord('core');
      final DocC docC = DocC(
        version: 5,
        candidates: <String, List<String>>{
          coord.key: <String>['https://rescue.cluster.atomi.cloud'],
        },
      );
      final FakeRescueStore store = FakeRescueStore(<String, String>{
        'docc': docC.encode(),
        'docc.version': '5',
        'doca.version': '9',
      });
      final FakeHttpTransport transport = FakeHttpTransport.byHost(
        <String, TransportOutcome>{
          'core.example.com': networkFailure('down'),
          'rescue.cluster.atomi.cloud': okJson(<String, Object?>{'ok': true}),
          'r2.example.com': networkFailure('doc host down'),
        },
      );
      final RescueConfig rescueConfig = RescueConfig(
        enabled: true,
        issuer: Uri.parse('https://auth.atomi.cloud'),
        catalogHosts: const <String>['r2.example.com'],
        endpointSuffixAllowlist: const <String>['.cluster.atomi.cloud'],
      );
      final RescueRouter router = RescueRouter(
        config: rescueConfig,
        store: store,
        transport: transport,
        sleep: noSleep,
        jitter: noJitter,
      );
      final ApiEngine engine = ApiEngine.fromConfig(
        ApiEngineConfig(
          backends: <BackendConfig>[
            BackendConfig(
              coordinate: coord,
              baseUrl: Uri.parse('https://core.example.com'),
            ),
          ],
          rescue: rescueConfig,
        ),
        transport: transport,
        rescueOverride: router,
      );

      final Result<Map<String, Object?>> result = await engine
          .backend(coord)!
          .call(method: HttpMethod.get, path: '/me', decode: _id);

      expect(expectOk(result)['ok'], true);
      expect(await store.read('pin.${coord.key}'),
          'https://rescue.cluster.atomi.cloud');
      expect(
        transport.sent.any(
          (HttpRequest r) => r.url.host == 'rescue.cluster.atomi.cloud',
        ),
        isTrue,
      );
    });
  });
}
