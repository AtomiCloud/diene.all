import 'session_controller.dart';

final class DemoAuthGateway implements AuthGateway {
  DemoAuthGateway({
    required this.accessLifetime,
    required this.refreshLifetime,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Duration accessLifetime;
  final Duration refreshLifetime;
  final DateTime Function() _now;
  int _rotation = 0;

  @override
  Future<SessionTokens> signIn() async => _issue(family: 'demo-family');

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
