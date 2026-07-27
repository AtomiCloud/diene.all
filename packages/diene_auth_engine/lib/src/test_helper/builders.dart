import 'dart:convert';

import '../auth/claims.dart';
import '../tokens/resource_key.dart';
import '../tokens/session_tokens.dart';
import '../tokens/token_lifetimes.dart';

/// Dependency-light builders for auth-engine tests. NO test-framework deps.
abstract final class AuthFixtures {
  /// Builds an unsigned JWT (header.payload.signature) whose payload carries
  /// [claims]. The signature is a fixed placeholder — the client only reads
  /// claims, never verifies here.
  static String jwt(Map<String, Object?> claims) {
    String seg(Map<String, Object?> value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final String header = seg(<String, Object?>{'alg': 'none', 'typ': 'JWT'});
    final String payload = seg(claims);
    return '$header.$payload.sig';
  }

  /// A JWT carrying the exact `<platform>_<service> = "true"` registration
  /// claim for [key], plus any [extra] claims.
  static String registeredJwt(
    ResourceKey key, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) => jwt(<String, Object?>{
    Claims.registrationKey(platform: key.platform, service: key.service):
        'true',
    ...extra,
  });

  /// A JWT lacking the registration claim for [key].
  static String unregisteredJwt(
    ResourceKey key, {
    Map<String, Object?> extra = const <String, Object?>{},
  }) => jwt(<String, Object?>{...extra});

  /// A [SessionTokens] pair with family-standard lifetimes anchored at [now].
  static SessionTokens sessionTokens({
    required DateTime now,
    String accessToken = 'access',
    String refreshToken = 'refresh',
    String refreshFamily = 'family',
    Duration access = TokenLifetimes.access,
    Duration refresh = TokenLifetimes.refresh,
  }) {
    final DateTime base = now.toUtc();
    return SessionTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      refreshFamily: refreshFamily,
      accessExpiresAt: base.add(access),
      refreshExpiresAt: base.add(refresh),
    );
  }

  /// A [ResourceToken] valid for [ttl] from [now], carrying [jwtToken].
  static ResourceToken resourceToken({
    required DateTime now,
    required String jwtToken,
    Duration ttl = TokenLifetimes.access,
  }) => ResourceToken(token: jwtToken, expiresAt: now.toUtc().add(ttl));

  /// A canonical example resource key.
  static ResourceKey resourceKey({
    String platform = 'lithium',
    String landscape = 'lapras',
    String service = 'api',
    String resourceName = 'root',
  }) => ResourceKey(
    platform: platform,
    landscape: landscape,
    service: service,
    resourceName: resourceName,
  );
}
