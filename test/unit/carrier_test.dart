import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const String nonce =
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'; // 43 chars
  const String canonical = 'atomi-app-handoff:v1:$nonce';

  test('parses the canonical carrier text', () {
    // Assert
    expect(AppHandoffCarrier.parseCanonical(canonical)?.nonce, nonce);
    expect(AppHandoffCarrier.parseCanonical('nope'), isNull);
    expect(
      AppHandoffCarrier.parseCanonical('atomi-app-handoff:v1:short'),
      isNull,
    );
  });

  test('round-trips through canonicalText', () {
    // Assert
    expect(
      AppHandoffCarrier.parseCanonical(canonical)?.canonicalText,
      canonical,
    );
  });

  test('extracts a single app_handoff field from the Android referrer', () {
    // Arrange
    final String referrer =
        'utm_source=store&app_handoff=${Uri.encodeComponent(canonical)}&x=1';

    // Assert
    expect(AppHandoffCarrier.parseAndroidReferrer(referrer)?.nonce, nonce);
  });

  test('treats zero or duplicate app_handoff fields as absent', () {
    // Arrange
    final String encoded = Uri.encodeComponent(canonical);

    // Assert
    expect(AppHandoffCarrier.parseAndroidReferrer('utm=1'), isNull);
    expect(
      AppHandoffCarrier.parseAndroidReferrer(
        'app_handoff=$encoded&app_handoff=$encoded',
      ),
      isNull,
    );
  });

  test('trims iOS clipboard whitespace', () {
    // Assert
    expect(AppHandoffCarrier.parseClipboard('  $canonical\n')?.nonce, nonce);
  });
}
