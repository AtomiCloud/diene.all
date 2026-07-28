import 'package:diene_auth_engine/diene_auth_engine.dart';

/// Demo-mode implementation of the published [AuthProvider].
///
/// Issues deterministic in-memory tokens so the app runs end-to-end without a
/// real IdP. The resource-token / id-token / claim-token members are not part
/// of the demo session path and fail closed if a caller reaches for them.
final class DemoAuthProvider implements AuthProvider {
  DemoAuthProvider({
    required this.accessLifetime,
    required this.refreshLifetime,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration accessLifetime;
  final Duration refreshLifetime;
  final DateTime Function() _now;
  int _rotation = 0;

  @override
  Future<SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) async => _issue(family: 'demo-family');

  @override
  Future<SessionTokens> refresh(SessionTokens current) async =>
      _issue(family: current.refreshFamily);

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) async {
    final DateTime now = _now().toUtc();
    return SessionTokens(
      accessToken: 'demo-access-open-${++_rotation}',
      refreshToken: current.refreshToken,
      refreshFamily: current.refreshFamily,
      accessExpiresAt: now.add(accessLifetime),
      refreshExpiresAt: current.refreshExpiresAt,
    );
  }

  @override
  Future<void> signOut() async {}

  @override
  Future<ResourceToken> resourceToken(ResourceKey key) =>
      throw UnsupportedError('Demo mode cannot mint ${key.mapKey}');

  @override
  Future<String?> idToken() async => null;

  @override
  Future<String?> freshClaimToken() async => null;

  SessionTokens _issue({required String family}) {
    final DateTime now = _now().toUtc();
    return SessionTokens(
      accessToken: 'demo-access-${++_rotation}',
      refreshToken: 'demo-refresh-$_rotation',
      refreshFamily: family,
      accessExpiresAt: now.add(accessLifetime),
      refreshExpiresAt: now.add(refreshLifetime),
    );
  }
}
