import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:diene_auth_engine/diene_auth_engine.dart' as auth;
import 'package:test/test.dart';

final class _Provider implements auth.AuthProvider {
  _Provider(this._resourceToken);

  final Future<auth.ResourceToken> Function(auth.ResourceKey key)
  _resourceToken;

  @override
  Future<auth.ResourceToken> resourceToken(auth.ResourceKey key) =>
      _resourceToken(key);

  @override
  Future<String?> freshClaimToken() async => null;

  @override
  Future<String?> idToken() async => null;

  @override
  Future<auth.SessionTokens> reMintOnOpen(auth.SessionTokens current) =>
      throw UnimplementedError();

  @override
  Future<auth.SessionTokens> refresh(auth.SessionTokens current) =>
      throw UnimplementedError();

  @override
  Future<auth.SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) => throw UnimplementedError();

  @override
  Future<void> signOut() async {}
}

final LpsmCoordinate _coordinate = LpsmCoordinate(
  landscape: 'lapras',
  platform: 'platform',
  service: 'service',
  module: 'core',
);

ApiEngine _engine(auth.IAuth authSeam, FakeHttpTransport transport) =>
    ApiEngine.fromConfig(
      ApiEngineConfig(
        backends: <BackendConfig>[
          BackendConfig(
            coordinate: _coordinate,
            baseUrl: Uri.parse('https://svc.example.com'),
            resourceName: 'core',
          ),
        ],
        rescue: RescueConfig(
          enabled: false,
          issuer: Uri.parse('https://unused.example'),
          catalogHosts: const <String>[],
          endpointSuffixAllowlist: const <String>[],
        ),
      ),
      auth: authSeam,
      transport: transport,
    );

Map<String, Object?> _identity(Map<String, Object?> json) => json;

void main() {
  group('accepted auth-engine seam compatibility', () {
    test('AuthCoordinator token success reaches the backend request', () async {
      final auth.AuthCoordinator authSeam = auth.AuthCoordinator(
        provider: _Provider(
          (auth.ResourceKey key) async => auth.ResourceToken(
            token: 'real-auth-token',
            expiresAt: DateTime.utc(2999),
          ),
        ),
      );
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => okJson(<String, Object?>{'ok': true}),
      );

      final Result<Map<String, Object?>> result =
          await _engine(authSeam, transport)
              .backend(_coordinate)!
              .call(method: HttpMethod.get, path: '/me', decode: _identity);

      expect(expectOk(result)['ok'], true);
      expect(
        transport.sent.single.headers['Authorization'],
        'Bearer real-auth-token',
      );
    });

    test('auth-owned failure becomes the shared Problem losslessly', () async {
      final auth.AuthCoordinator authSeam = auth.AuthCoordinator(
        provider: _Provider(
          (auth.ResourceKey key) async => throw StateError('token denied'),
        ),
      );
      final FakeHttpTransport transport = FakeHttpTransport(
        (HttpRequest request) => okJson(<String, Object?>{'unexpected': true}),
      );

      final Result<Map<String, Object?>> result =
          await _engine(authSeam, transport)
              .backend(_coordinate)!
              .call(method: HttpMethod.get, path: '/me', decode: _identity);

      final Problem problem = expectErr(result);
      expect(problem.type, 'urn:diene:problem:resource-token');
      expect(problem.title, 'Could not acquire a resource token');
      expect(problem.status, 401);
      expect(problem.detail, contains('token denied'));
      expect(problem.recoverable, true);
      expect(problem.data['resource'], 'platform/lapras/service/core');
      expect(transport.callCount, 0);
    });
  });
}
