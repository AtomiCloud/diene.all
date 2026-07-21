import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

// Adapter-level regressions for the real LogtoAuthProvider claim-bearing-token
// seam. These exercise `freshClaimToken` (the forced post-OnboardSync read)
// WITHOUT a live IdP: construction does no network, and freshClaimToken only
// touches the injected refresher seam / fail-closed branch.
void main() {
  final AuthEngineConfig config = AuthEngineConfig.fromBlock(<String, Object?>{
    'issuer': 'https://api.lithium.platform.mew.cluster.atomi.cloud',
    'endpoint': 'https://logto.example.com',
    'appId': 'mobile',
    'redirectUri': 'cloud.atomi.app://callback',
  });
  final ResourceKey key = AuthFixtures.resourceKey();

  test('freshClaimToken fails closed when no refresher is wired', () async {
    // Arrange — the stock SDK cannot force-refresh a still-valid token, so
    // without a platform-supplied refresher the adapter must NOT return a
    // possibly-stale token.
    final LogtoAuthProvider provider = LogtoAuthProvider(
      config: config,
      primaryResource: key,
    );

    // Act + Assert
    expect(await provider.freshClaimToken(), isNull);
  });

  test('freshClaimToken returns the exact injected refresher token', () async {
    // Arrange — the platform wires a guaranteed-fresh claim-bearing token.
    const String fresh = 'header.fresh-claim-payload.sig';
    final LogtoAuthProvider provider = LogtoAuthProvider(
      config: config,
      primaryResource: key,
      claimTokenRefresher: () async => fresh,
    );

    // Act + Assert — the returned token is exactly what the parser will decode.
    expect(await provider.freshClaimToken(), fresh);
  });

  test(
    'freshClaimToken maps a blank refresher result to null (fail closed)',
    () async {
      // Arrange
      final LogtoAuthProvider provider = LogtoAuthProvider(
        config: config,
        primaryResource: key,
        claimTokenRefresher: () async => '',
      );

      // Act + Assert
      expect(await provider.freshClaimToken(), isNull);
    },
  );
}
