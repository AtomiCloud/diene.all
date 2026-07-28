import 'package:diene_auth_engine/diene_auth_engine.dart' as diene_auth;
import 'package:logto_dart_sdk/logto_dart_sdk.dart' show LogtoClient;

import '../config/app_config.dart';
import 'session_controller.dart';

/// Compatibility facade over diene_auth_engine's Logto provider.
final class LogtoAuthGateway implements AuthGateway {
  LogtoAuthGateway({
    required AppConfig config,
    LogtoClient? client,
    DateTime Function()? now,
  }) : _provider = diene_auth.LogtoAuthProvider(
         config: _engineConfig(config),
         primaryResource: _primaryResource(config),
         client: client,
         now: now,
       );

  final diene_auth.LogtoAuthProvider _provider;

  @override
  Future<diene_auth.SessionTokens> signIn() => _provider.signIn();

  @override
  Future<diene_auth.SessionTokens> refresh(diene_auth.SessionTokens current) =>
      _provider.refresh(current);

  @override
  Future<diene_auth.SessionTokens> reMintOnOpen(
    diene_auth.SessionTokens current,
  ) => _provider.reMintOnOpen(current);

  @override
  Future<void> signOut() => _provider.signOut();
}

diene_auth.AuthEngineConfig _engineConfig(AppConfig config) =>
    diene_auth.AuthEngineConfig(
      // The compatibility config predates the separate issuer field. Logto's
      // endpoint is its issuer here, as it was for the former SDK transport.
      issuer: config.auth.endpoint,
      endpoint: config.auth.endpoint,
      appId: config.auth.clientId,
      redirectUri: config.auth.redirectUri,
      scopes: config.auth.scopes,
    );

diene_auth.ResourceKey _primaryResource(AppConfig config) {
  // The legacy audience URI supplies the resource/M-slot name. The engine
  // owns construction of the canonical LPSM audience from that name and the
  // app's baked identity.
  final String resourceName = config.auth.resource.host.split('.').first;
  return diene_auth.ResourceKey(
    platform: config.identity.platform,
    landscape: config.identity.landscape,
    service: config.identity.service,
    resourceName: resourceName,
  );
}
