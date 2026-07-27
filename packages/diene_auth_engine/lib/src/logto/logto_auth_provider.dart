import 'package:http/http.dart' as http;
import 'package:logto_dart_sdk/logto_dart_sdk.dart';

import '../auth/auth_provider.dart';
import '../config/auth_engine_config.dart';
import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';
import '../tokens/token_lifetimes.dart';

/// The Logto implementation of [AuthProvider] — the only provider in v1.
///
/// PARITY DELTA (documented): Logto's SDK OWNS refresh-token rotation and reuse
/// detection internally (`getAccessToken` refreshes behind the seam and never
/// surfaces the refresh token). This adapter therefore synthesizes the family
/// [SessionTokens] refresh bookkeeping; the rotating-reuse guarantee that
/// [SessionController] enforces is exercised through provider fakes and applies
/// verbatim to any provider that DOES surface refresh tokens.
final class LogtoAuthProvider implements AuthProvider {
  LogtoAuthProvider({
    required AuthEngineConfig config,
    required ResourceKey primaryResource,
    List<ResourceKey> resources = const <ResourceKey>[],
    LogtoClient? client,
    http.Client? httpClient,
    DateTime Function()? now,
    this._claimTokenRefresher,
  }) : _config = config,
       _primaryResource = primaryResource,
       _now = now ?? DateTime.now,
       _client =
           client ??
           LogtoClient(
             config: LogtoConfig(
               endpoint: config.endpoint.toString(),
               appId: config.appId,
               scopes: config.scopes,
               resources: <String>[
                 for (final ResourceKey key in <ResourceKey>{
                   primaryResource,
                   ...resources,
                 })
                   key.audience.toString(),
               ],
             ),
             httpClient: httpClient ?? http.Client(),
           );

  final AuthEngineConfig _config;
  final ResourceKey _primaryResource;
  final LogtoClient _client;
  final DateTime Function() _now;
  final Future<String?> Function()? _claimTokenRefresher;
  int _rotation = 0;

  @override
  Future<SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) async {
    final Map<String, String> extras = Map<String, String>.of(extraParams);
    final String? loginHint = extras.remove('login_hint');
    await _client.signIn(
      _config.redirectUri.toString(),
      loginHint: loginHint,
      extraParams: extras.isEmpty ? null : extras,
    );
    return _issue(refreshFamily: 'logto-sdk');
  }

  @override
  Future<SessionTokens> refresh(SessionTokens current) async =>
      _issue(refreshFamily: current.refreshFamily);

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) async {
    final _ResolvedAccess access = await _access(_primaryResource);
    return SessionTokens(
      accessToken: access.token,
      refreshToken: current.refreshToken,
      refreshFamily: current.refreshFamily,
      accessExpiresAt: access.expiresAt,
      refreshExpiresAt: current.refreshExpiresAt,
    );
  }

  @override
  Future<void> signOut() => _client.signOut(_config.redirectUri.toString());

  @override
  Future<ResourceToken> resourceToken(ResourceKey key) async {
    final _ResolvedAccess access = await _access(key);
    return ResourceToken(token: access.token, expiresAt: access.expiresAt);
  }

  @override
  Future<String?> idToken() => _client.idToken;

  @override
  Future<String?> freshClaimToken() async {
    // logto_dart_sdk v3 exposes NO public force-refresh / cache-invalidation for
    // a still-valid token: `getAccessToken` returns the stored token when one
    // exists and `idToken` reads token storage directly. A just-minted 10-minute
    // signup access token is therefore a cache hit, so reading it back would NOT
    // reflect an OnboardSync-updated `home_landscape` claim.
    //
    // The guaranteed-fresh claim-bearing token is supplied through the injected
    // [claimTokenRefresher] seam (platform wiring — e.g. a forced token refresh
    // via re-authentication or a management-backed claim read). Its EXACT
    // returned token is what the caller decodes. When no refresher is wired we
    // FAIL CLOSED (return null) rather than hand back a possibly-stale token.
    final Future<String?> Function()? refresher = _claimTokenRefresher;
    if (refresher == null) {
      return null;
    }
    final String? token = await refresher();
    if (token == null || token.isEmpty) {
      return null;
    }
    return token;
  }

  Future<SessionTokens> _issue({required String refreshFamily}) async {
    final _ResolvedAccess access = await _access(_primaryResource);
    final DateTime now = _now().toUtc();
    return SessionTokens(
      accessToken: access.token,
      refreshToken: 'logto-refresh-${++_rotation}',
      refreshFamily: refreshFamily,
      accessExpiresAt: access.expiresAt,
      refreshExpiresAt: now.add(TokenLifetimes.refresh),
    );
  }

  Future<_ResolvedAccess> _access(ResourceKey key) async {
    final AccessToken? token = await _client.getAccessToken(
      resource: key.audience.toString(),
    );
    if (token == null) {
      throw StateError(
        'Logto did not return an access token for ${key.mapKey}',
      );
    }
    return _ResolvedAccess(token.token, token.expiresAt.toUtc());
  }
}

final class _ResolvedAccess {
  const _ResolvedAccess(this.token, this.expiresAt);

  final String token;
  final DateTime expiresAt;
}
