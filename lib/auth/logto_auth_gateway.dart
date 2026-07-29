import 'package:http/http.dart' as http;
import 'package:logto_dart_sdk/logto_dart_sdk.dart';

import '../config/app_config.dart';
import 'session_controller.dart';

final class LogtoAuthGateway implements AuthGateway {
  LogtoAuthGateway({
    required AppConfig config,
    LogtoClient? client,
    DateTime Function()? now,
  }) : _config = config,
       _client =
           client ??
           LogtoClient(
             config: LogtoConfig(
               endpoint: config.auth.endpoint.toString(),
               appId: config.auth.clientId,
               scopes: config.auth.scopes,
               resources: <String>[config.auth.resource.toString()],
             ),
             httpClient: http.Client(),
           ),
       _now = now ?? DateTime.now;

  final AppConfig _config;
  final LogtoClient _client;
  final DateTime Function() _now;
  int _rotation = 0;

  @override
  Future<SessionTokens> signIn() async {
    await _client.signIn(_config.auth.redirectUri.toString());
    return _tokens(
      await _accessToken(),
      refreshToken: 'sdk-refresh-${++_rotation}',
      refreshFamily: 'logto-sdk',
    );
  }

  @override
  Future<SessionTokens> refresh(SessionTokens current) async => _tokens(
    await _accessToken(),
    refreshToken: 'sdk-refresh-${++_rotation}',
    refreshFamily: current.refreshFamily,
  );

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) async => _tokens(
    await _accessToken(),
    refreshToken: current.refreshToken,
    refreshFamily: current.refreshFamily,
  );

  @override
  Future<void> signOut() =>
      _client.signOut(_config.auth.redirectUri.toString());

  Future<String> _accessToken() async {
    final token = await _client.getAccessToken(
      resource: _config.auth.resource.toString(),
    );
    if (token == null) {
      throw StateError('Logto did not return an access token');
    }
    return token.token;
  }

  SessionTokens _tokens(
    String accessToken, {
    required String refreshToken,
    required String refreshFamily,
  }) {
    final DateTime now = _now().toUtc();
    return SessionTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      refreshFamily: refreshFamily,
      accessExpiresAt: now.add(_config.session.accessLifetime),
      refreshExpiresAt: now.add(_config.session.refreshLifetime),
    );
  }
}
