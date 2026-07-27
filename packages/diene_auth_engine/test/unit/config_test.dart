import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> block() => <String, Object?>{
    'issuer': 'https://api.lithium.platform.mew.cluster.atomi.cloud',
    'endpoint': 'https://logto.example.com',
    'appId': 'mobile',
    'redirectUri': 'cloud.atomi.app://callback',
    'scopes': <String>['openid', 'offline_access'],
  };

  test('parses a valid block and defaults the mount', () {
    // Act
    final AuthEngineConfig config = AuthEngineConfig.fromBlock(block());

    // Assert
    expect(config.appId, 'mobile');
    expect(config.appHandoffMount, '/app-handoff');
    expect(config.redeemPath, '/app-handoff/redeem');
  });

  test('a configurable mount changes the redeem path', () {
    // Act
    final AuthEngineConfig config = AuthEngineConfig.fromBlock(
      <String, Object?>{...block(), 'appHandoffMount': '/handoff'},
    );

    // Assert
    expect(config.redeemPath, '/handoff/redeem');
  });

  test('fails fast on a missing required key (baked issuer)', () {
    // Arrange
    final Map<String, Object?> bad = block()..remove('issuer');

    // Assert
    expect(() => AuthEngineConfig.fromBlock(bad), throwsFormatException);
  });

  test('enforces the baked endpoint-suffix allowlist', () {
    // Arrange
    final AuthEngineConfig config = AuthEngineConfig.fromBlock(block());

    // Assert
    expect(
      config.allowsUrl(Uri.parse('https://b.pichu.cluster.atomi.cloud/doc')),
      isTrue,
    );
    expect(config.allowsUrl(Uri.parse('https://evil.example/doc')), isFalse);
  });

  test('exposes the declarative block schema and fixed constants', () {
    // Assert
    expect(AuthEngineConfig.blockSchema[r'$id'], 'authEngine');
    expect(AppHandoffConstants.nonceTtl, const Duration(minutes: 15));
    expect(AppHandoffConstants.oneTimeTokenExpiresInSeconds, 120);
  });
}
