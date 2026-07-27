import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registration key lowercases and replaces dashes with underscores', () {
    // Assert
    expect(
      Claims.registrationKey(platform: 'Lith-ium', service: 'API-x'),
      'lith_ium_api_x',
    );
  });

  test('hasRegistration requires the exact JSON string "true"', () {
    // Arrange
    final Map<String, Object?> yes = Claims.decode(
      AuthFixtures.jwt(<String, Object?>{'lithium_api': 'true'}),
    );
    final Map<String, Object?> boolTrue = Claims.decode(
      AuthFixtures.jwt(<String, Object?>{'lithium_api': true}),
    );
    final Map<String, Object?> missing = Claims.decode(
      AuthFixtures.jwt(<String, Object?>{'other': 'true'}),
    );

    // Assert — only the string "true" counts.
    expect(
      Claims.hasRegistration(yes, platform: 'lithium', service: 'api'),
      isTrue,
    );
    expect(
      Claims.hasRegistration(boolTrue, platform: 'lithium', service: 'api'),
      isFalse,
    );
    expect(
      Claims.hasRegistration(missing, platform: 'lithium', service: 'api'),
      isFalse,
    );
  });

  test('home reads a non-empty home_landscape claim', () {
    // Arrange
    final Map<String, Object?> present = Claims.decode(
      AuthFixtures.jwt(<String, Object?>{Claims.homeLandscape: 'pichu'}),
    );
    final Map<String, Object?> blank = Claims.decode(
      AuthFixtures.jwt(<String, Object?>{Claims.homeLandscape: ''}),
    );

    // Assert
    expect(Claims.home(present), 'pichu');
    expect(Claims.home(blank), isNull);
  });

  test('decode tolerates a structurally invalid token', () {
    // Assert
    expect(Claims.decode('not-a-jwt'), isEmpty);
  });
}
