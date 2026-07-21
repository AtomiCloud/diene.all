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

void main() {
  group('multi-backend', () {
    test('each backend carries its OWN token — no cross-backend bleed',
        () async {
      // Arrange: two backends, tokens keyed per coordinate.
      final ApiEngineConfig config = ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coord('a'),
            baseUrl: Uri.parse('https://a.example.com'),
          ),
          BackendConfig(
            coordinate: _coord('b'),
            baseUrl: Uri.parse('https://b.example.com'),
          ),
        ],
        rescue: RescueConfig(
          enabled: false,
          // Disabled rescue never reads the issuer; a placeholder is fine.
          issuer: Uri.parse('https://unused.example'),
          catalogHosts: const <String>[],
          endpointSuffixAllowlist: const <String>[],
        ),
      );
      final FakeHttpTransport transport = FakeHttpTransport.byHost(
        <String, TransportOutcome>{
          'a.example.com': okJson(<String, Object?>{'who': 'a'}),
          'b.example.com': okJson(<String, Object?>{'who': 'b'}),
        },
      );
      final FakeAuth auth = FakeAuth(<String, String>{
        'lapras.platform.service.a': 'token-a',
        'lapras.platform.service.b': 'token-b',
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
    });
  });

  group('rescue trip', () {
    test('hard failure trips the router, pins a rescued address, and succeeds',
        () async {
      // Arrange
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
        auth: const AnonymousAuth(),
        transport: transport,
        rescueOverride: router,
      );

      // Act
      final Result<Map<String, Object?>> result = await engine
          .backend(coord)!
          .call(method: HttpMethod.get, path: '/me', decode: _id);

      // Assert
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
