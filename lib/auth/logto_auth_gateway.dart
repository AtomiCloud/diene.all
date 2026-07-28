import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:logto_dart_sdk/logto_dart_sdk.dart' show LogtoClient;

import '../config/app_config.dart';

/// Builds the published [LogtoAuthProvider] from the app's [AppConfig].
///
/// This is app-side dependency wiring, not a seam: it translates the app's
/// typed configuration into the engine's [AuthEngineConfig] / [ResourceKey] and
/// hands back the published provider the rest of the app consumes directly.
LogtoAuthProvider logtoAuthProvider(
  AppConfig config, {
  LogtoClient? client,
  DateTime Function()? now,
}) => LogtoAuthProvider(
  config: _engineConfig(config),
  primaryResource: _primaryResource(config),
  client: client,
  now: now,
);

AuthEngineConfig _engineConfig(AppConfig config) => AuthEngineConfig(
  // Logto's endpoint is its issuer here, as it was for the former SDK
  // transport; the app config predates a separate issuer field.
  issuer: config.auth.endpoint,
  endpoint: config.auth.endpoint,
  appId: config.auth.clientId,
  redirectUri: config.auth.redirectUri,
  scopes: config.auth.scopes,
);

ResourceKey _primaryResource(AppConfig config) {
  // The audience URI supplies the resource/M-slot name. The engine owns
  // construction of the canonical LPSM audience from that name and the app's
  // baked identity.
  final String resourceName = config.auth.resource.host.split('.').first;
  return ResourceKey(
    platform: config.identity.platform,
    landscape: config.identity.landscape,
    service: config.identity.service,
    resourceName: resourceName,
  );
}
