import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21, 12);
  SessionTokens issued({String refresh = 'r1', String family = 'fam'}) =>
      AuthFixtures.sessionTokens(
        now: now,
        refreshToken: refresh,
        refreshFamily: family,
      );

  test(
    'signIn enforces the 10m/14d lifetimes and passes extraParams',
    () async {
      // Arrange
      final FakeAuthProvider provider = FakeAuthProvider(onSignIn: issued);
      final SessionController session = SessionController(
        provider: provider,
        now: () => now,
      );

      // Act
      final Result<SessionTokens> result = await session.signIn(
        extraParams: <String, String>{'one_time_token': 't'},
      );

      // Assert
      final SessionTokens tokens = AuthExpect.ok(result);
      expect(tokens.accessExpiresAt.difference(now), TokenLifetimes.access);
      expect(tokens.refreshExpiresAt.difference(now), TokenLifetimes.refresh);
      expect(session.status, SessionStatus.authenticated);
      expect(provider.lastExtraParams['one_time_token'], 't');
    },
  );

  test('rejects an over-long access lifetime', () async {
    // Arrange
    final FakeAuthProvider provider = FakeAuthProvider(
      onSignIn: () => SessionTokens(
        accessToken: 'a',
        refreshToken: 'r',
        refreshFamily: 'f',
        accessExpiresAt: now.add(const Duration(minutes: 20)),
        refreshExpiresAt: now.add(TokenLifetimes.refresh),
      ),
    );
    final SessionController session = SessionController(
      provider: provider,
      now: () => now,
    );

    // Act
    final Result<SessionTokens> result = await session.signIn();

    // Assert
    expect(result, isA<Failure<SessionTokens>>());
    expect(session.status, SessionStatus.failed);
  });

  test('refresh rotates the refresh token', () async {
    // Arrange
    final FakeAuthProvider provider = FakeAuthProvider(
      onSignIn: () => issued(refresh: 'r1'),
      onRefresh: (SessionTokens c) =>
          issued(refresh: 'r2', family: c.refreshFamily),
    );
    final SessionController session = SessionController(
      provider: provider,
      now: () => now,
    );
    await session.signIn();

    // Act
    final Result<SessionTokens> result = await session.refresh();

    // Assert
    expect(AuthExpect.ok(result).refreshToken, 'r2');
  });

  test('refresh-token reuse signs out the whole session', () async {
    // Arrange — provider hands back the SAME refresh token (reuse/theft).
    final FakeAuthProvider provider = FakeAuthProvider(
      onSignIn: () => issued(refresh: 'r1'),
      onRefresh: (SessionTokens c) =>
          issued(refresh: 'r1', family: c.refreshFamily),
    );
    final SessionController session = SessionController(
      provider: provider,
      now: () => now,
    );
    await session.signIn();

    // Act
    final Result<SessionTokens> result = await session.refresh();

    // Assert
    expect(AuthExpect.err(result).type, 'urn:diene:problem:refresh-reuse');
    expect(session.status, SessionStatus.unauthenticated);
    expect(session.tokens, isNull);
    expect(provider.signOutCount, 1);
  });

  test(
    'onAppOpen re-mints the access token keeping the refresh token',
    () async {
      // Arrange
      final FakeAuthProvider provider = FakeAuthProvider(
        onSignIn: () => issued(refresh: 'r1'),
        onReMint: (SessionTokens c) => SessionTokens(
          accessToken: 'fresh',
          refreshToken: c.refreshToken,
          refreshFamily: c.refreshFamily,
          accessExpiresAt: now.add(TokenLifetimes.access),
          refreshExpiresAt: c.refreshExpiresAt,
        ),
      );
      final SessionController session = SessionController(
        provider: provider,
        now: () => now,
      );
      await session.signIn();

      // Act
      final Result<SessionTokens> result = await session.onAppOpen();

      // Assert
      expect(AuthExpect.ok(result).accessToken, 'fresh');
      expect(provider.reMintCount, 1);
    },
  );

  test('refresh fails when there is no session', () async {
    // Arrange
    final SessionController session = SessionController(
      provider: FakeAuthProvider(),
      now: () => now,
    );

    // Act + Assert
    expect((await session.refresh()), isA<Failure<SessionTokens>>());
    expect((await session.onAppOpen()), isA<Failure<SessionTokens>>());
  });
}
