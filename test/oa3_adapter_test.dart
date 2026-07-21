import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/src/generated/export.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:test/test.dart';

final LpsmCoordinate _coord = LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: 'core',
);

RescueConfig _disabledRescue() => RescueConfig(
  enabled: false,
  issuer: Uri.parse('https://unused.example'),
  catalogHosts: const <String>[],
  endpointSuffixAllowlist: const <String>[],
);

ApiEngine _engine(
  HttpTransport transport, {
  IAuth? auth,
  RescueConfig? rescue,
  RescueRouter? rescueOverride,
}) => ApiEngine.fromConfig(
  ApiEngineConfig(
    backends: <BackendConfig>[
      BackendConfig(
        coordinate: _coord,
        baseUrl: Uri.parse('https://svc.example.com'),
        resourceName: auth == null ? null : 'core',
      ),
    ],
    rescue: rescue ?? _disabledRescue(),
  ),
  auth: auth,
  transport: transport,
  rescueOverride: rescueOverride,
);

void main() {
  group('OA3 SDK wired into the production Backend pipeline', () {
    test(
      '200 → Ok(typed) with the backend base URL + per-resource token',
      () async {
        final FakeHttpTransport transport = FakeHttpTransport.byHost(
          <String, TransportOutcome>{
            'svc.example.com': okJson(<String, Object?>{
              'id': '1',
              'email': 'a@b.com',
            }),
          },
        );
        final ApiEngine engine = _engine(
          transport,
          auth: FakeAuth(<String, String>{
            'platform/lapras/service/core': 'tok',
          }),
        );
        final ServiceSdk sdk = engine.backend(_coord)!.sdk(ServiceSdk.new);

        final Result<UserProfile> result = await const ResultSdk().call(
          () => sdk.users.getUser(id: '1'),
        );

        final UserProfile user = expectOk(result);
        expect(user.id, '1');
        // The generated call went through the backend's base URL and carried its
        // per-resource token (production wiring, not an isolated adapter).
        expect(transport.sent.single.url.host, 'svc.example.com');
        expect(transport.sent.single.headers['Authorization'], 'Bearer tok');
      },
    );

    test('404 problem body → Err(that Problem)', () async {
      final FakeHttpTransport transport =
          FakeHttpTransport.byHost(<String, TransportOutcome>{
            'svc.example.com': problemResponse(
              problemFixture(
                type: 'urn:diene:problem:entity-not-found',
                status: 404,
              ),
            ),
          });
      final ServiceSdk sdk = _engine(
        transport,
      ).backend(_coord)!.sdk(ServiceSdk.new);

      final Result<UserProfile> result = await const ResultSdk().call(
        () => sdk.users.getUser(id: '404'),
      );

      expect(expectErr(result).type, 'urn:diene:problem:entity-not-found');
    });

    test('retry-once then success → Ok (backend retry-once profile)', () async {
      final FakeHttpTransport transport = FakeHttpTransport.sequence(
        <TransportOutcome>[
          networkFailure('reset'),
          okJson(<String, Object?>{'id': '2', 'email': 'c@d.com'}),
        ],
      );
      final ServiceSdk sdk = _engine(
        transport,
      ).backend(_coord)!.sdk(ServiceSdk.new);

      final Result<UserProfile> result = await const ResultSdk().call(
        () => sdk.users.getUser(id: '2'),
      );

      expect(expectOk(result).id, '2');
      expect(transport.callCount, 2);
    });

    test(
      'hard failure trips the backend rescue router → Ok from rescued host',
      () async {
        final DocC docC = DocC(
          version: 1,
          candidates: <String, List<String>>{
            _coord.key: <String>['https://rescue.cluster.atomi.cloud'],
          },
        );
        final FakeRescueStore store = FakeRescueStore(<String, String>{
          'docc.${_coord.platform}.${_coord.landscape}': docC.encode(),
          'docc.version.${_coord.platform}.${_coord.landscape}': '1',
          'doca.version': '9',
        });
        final FakeHttpTransport transport = FakeHttpTransport.byHost(
          <String, TransportOutcome>{
            'svc.example.com': networkFailure('down'),
            'rescue.cluster.atomi.cloud': okJson(<String, Object?>{
              'id': '3',
              'email': 'e@f.com',
            }),
          },
        );
        final RescueConfig rescueConfig = RescueConfig(
          enabled: true,
          issuer: Uri.parse('https://auth.atomi.cloud'),
          catalogHosts: const <String>[],
          endpointSuffixAllowlist: const <String>['.cluster.atomi.cloud'],
        );
        final ApiEngine engine = _engine(
          transport,
          rescue: rescueConfig,
          rescueOverride: RescueRouter(
            config: rescueConfig,
            store: store,
            transport: transport,
            sleep: noSleep,
            jitter: noJitter,
          ),
        );
        final ServiceSdk sdk = engine.backend(_coord)!.sdk(ServiceSdk.new);

        final Result<UserProfile> result = await const ResultSdk().call(
          () => sdk.users.getUser(id: '3'),
        );

        expect(expectOk(result).id, '3');
        expect(
          transport.sent.any(
            (HttpRequest r) => r.url.host == 'rescue.cluster.atomi.cloud',
          ),
          isTrue,
        );
      },
    );

    test('token failure → Err (fail-closed), no HTTP attempted', () async {
      final FakeHttpTransport transport = FakeHttpTransport.byHost(
        <String, TransportOutcome>{
          'svc.example.com': okJson(<String, Object?>{
            'id': '1',
            'email': 'a@b.com',
          }),
        },
      );
      final ServiceSdk sdk = _engine(
        transport,
        auth: FakeAuth(<String, String>{}), // no token for the resource key
      ).backend(_coord)!.sdk(ServiceSdk.new);

      final Result<UserProfile> result = await const ResultSdk().call(
        () => sdk.users.getUser(id: '1'),
      );

      expect(result.isErr, isTrue);
      expect(transport.callCount, 0);
    });
  });
}
