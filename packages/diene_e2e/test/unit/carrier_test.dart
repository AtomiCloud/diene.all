import 'package:diene_e2e/diene_e2e.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A syntactically valid 43-char base64url nonce.
  const String nonce = 'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0U1v';

  group('nonce validation', () {
    test('accepts a 43-char base64url string', () {
      // Arrange / Act / Assert.
      expect(isValidAppHandoffNonce(nonce), isTrue);
    });

    test('rejects wrong length', () {
      expect(isValidAppHandoffNonce('${nonce}x'), isFalse);
      expect(isValidAppHandoffNonce(nonce.substring(1)), isFalse);
    });

    test('rejects non-base64url characters', () {
      // Arrange: replace one char with a padding '='.
      final String bad = '=${nonce.substring(1)}';
      // Act / Assert.
      expect(isValidAppHandoffNonce(bad), isFalse);
    });
  });

  group('canonical carrier', () {
    test('build then parse round-trips the nonce', () {
      // Arrange / Act.
      final String carrier = buildAppHandoffCarrier(nonce);
      // Assert.
      expect(carrier, 'atomi-app-handoff:v1:$nonce');
      expect(parseAppHandoffCarrier(carrier), nonce);
    });

    test('build throws on an invalid nonce', () {
      expect(() => buildAppHandoffCarrier('short'), throwsArgumentError);
    });

    test('parse returns null for absent or malformed carrier', () {
      expect(parseAppHandoffCarrier(null), isNull);
      expect(parseAppHandoffCarrier('atomi-app-handoff:v2:$nonce'), isNull);
      expect(parseAppHandoffCarrier('atomi-app-handoff:v1:short'), isNull);
      expect(parseAppHandoffCarrier('garbage'), isNull);
    });
  });

  group('install referrer', () {
    test('single app_handoff field round-trips', () {
      // Arrange.
      final String referrer = buildAppHandoffInstallReferrer(nonce);
      // Act / Assert.
      expect(parseAppHandoffInstallReferrer(referrer), nonce);
    });

    test('coexisting campaign fields are ignored', () {
      final String referrer = buildAppHandoffInstallReferrer(
        nonce,
        extraFields: <String, String>{'utm_source': 'x', 'utm_campaign': 'y'},
      );
      expect(parseAppHandoffInstallReferrer(referrer), nonce);
    });

    test('duplicate app_handoff fields are treated as absent', () {
      final String single = buildAppHandoffInstallReferrer(nonce);
      final String duplicated = '$single&$single';
      expect(parseAppHandoffInstallReferrer(duplicated), isNull);
    });

    test('zero app_handoff fields is absent', () {
      expect(parseAppHandoffInstallReferrer('utm_source=x'), isNull);
      expect(parseAppHandoffInstallReferrer(''), isNull);
      expect(parseAppHandoffInstallReferrer(null), isNull);
    });
  });

  group('clipboard', () {
    test('trims leading/trailing ascii whitespace', () {
      final String carrier = buildAppHandoffCarrier(nonce);
      expect(parseAppHandoffClipboard('  \t$carrier\n '), nonce);
    });

    test('malformed clipboard is absent', () {
      expect(parseAppHandoffClipboard('not a carrier'), isNull);
    });
  });
}
