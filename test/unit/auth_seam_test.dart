import 'dart:async';

import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

/// Provider that gates each acquisition on a [Completer] so the test can force
/// concurrent callers to collide.
final class _GatedProvider implements AuthProvider {
  int calls = 0;
  final Completer<void> gate = Completer<void>();
  final DateTime now = DateTime.utc(2026, 7, 21);

  @override
  Future<ResourceToken> resourceToken(ResourceKey key) async {
    calls += 1;
    await gate.future;
    return ResourceToken(
      token: 'tok-$calls',
      expiresAt: now.add(TokenLifetimes.access),
    );
  }

  @override
  Future<SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) => throw UnimplementedError();
  @override
  Future<SessionTokens> refresh(SessionTokens current) =>
      throw UnimplementedError();
  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) =>
      throw UnimplementedError();
  @override
  Future<void> signOut() async {}
  @override
  Future<String?> idToken() async => null;
}

void main() {
  final DateTime now = DateTime.utc(2026, 7, 21);
  final ResourceKey key = AuthFixtures.resourceKey();

  test('resource-key audience follows the C0 §8 template', () {
    // Assert
    expect(
      key.audience.toString(),
      'https://root.api.lithium.lapras.cluster.atomi.cloud',
    );
    expect(key.mapKey, 'lithium/lapras/api/root');
  });

  test('single-flight: concurrent callers share one acquisition', () async {
    // Arrange
    final _GatedProvider provider = _GatedProvider();
    final AuthCoordinator auth = AuthCoordinator(
      provider: provider,
      now: () => now,
    );

    // Act — three concurrent callers for the SAME key.
    final Future<Result<ResourceToken>> a = auth.tokenFor(key);
    final Future<Result<ResourceToken>> b = auth.tokenFor(key);
    final Future<Result<ResourceToken>> c = auth.tokenFor(key);
    provider.gate.complete();
    final List<Result<ResourceToken>> results = await Future.wait(
      <Future<Result<ResourceToken>>>[a, b, c],
    );

    // Assert — exactly one provider hit, all callers get the same token.
    expect(provider.calls, 1);
    expect(AuthExpect.ok(results[0]).token, 'tok-1');
    expect(AuthExpect.ok(results[2]).token, 'tok-1');
  });

  test(
    'cache serves the second call without re-hitting the provider',
    () async {
      // Arrange
      final _GatedProvider provider = _GatedProvider()..gate.complete();
      final AuthCoordinator auth = AuthCoordinator(
        provider: provider,
        now: () => now,
      );

      // Act
      await auth.tokenFor(key);
      await auth.tokenFor(key);

      // Assert
      expect(provider.calls, 1);

      // After invalidation, a fresh acquisition happens.
      auth.invalidate(key);
      await auth.tokenFor(key);
      expect(provider.calls, 2);
    },
  );

  test(
    'fetchAllTokens dedups by full key and returns one entry per key',
    () async {
      // Arrange
      final FakeAuthProvider provider = FakeAuthProvider(
        resourceTokens: <String, ResourceToken>{
          key.mapKey: AuthFixtures.resourceToken(now: now, jwtToken: 'j'),
        },
      );
      final AuthCoordinator auth = AuthCoordinator(
        provider: provider,
        now: () => now,
      );

      // Act — the same key twice must resolve to a single entry.
      final Map<ResourceKey, Result<ResourceToken>> batch = await auth
          .fetchAllTokens(<ResourceKey>[key, key]);

      // Assert
      expect(batch.length, 1);
      expect(AuthExpect.ok(batch[key]!).token, 'j');
    },
  );
}
