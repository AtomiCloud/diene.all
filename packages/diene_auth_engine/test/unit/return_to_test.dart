import 'package:diene_auth_engine/diene_auth_engine.dart';
import 'package:diene_auth_engine/test_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('captures a relative target preserving path and query', () {
    // Act
    final Result<String> captured = ReturnTo.capture(
      Uri.parse('/orders/42?tab=items&sort=asc'),
    );

    // Assert
    expect(AuthExpect.ok(captured), '/orders/42?tab=items&sort=asc');
  });

  test('rejects open-redirect targets', () {
    // Assert
    expect(
      ReturnTo.capture(Uri.parse('https://evil.example/x')),
      isA<Failure<String>>(),
    );
    expect(ReturnTo.resolve('//evil.example/x'), isA<Failure<Uri>>());
    expect(ReturnTo.resolve('/\\evil'), isA<Failure<Uri>>());
    expect(ReturnTo.resolve('https://evil'), isA<Failure<Uri>>());
  });

  test('builds a login redirect carrying the returnTo', () {
    // Act
    final Result<Uri> redirect = ReturnTo.buildLoginRedirect(
      Uri.parse('/login'),
      Uri.parse('/secret?x=1'),
    );

    // Assert
    final Uri uri = AuthExpect.ok(redirect);
    expect(uri.queryParameters['returnTo'], '/secret?x=1');
  });

  test('resolves the exact target and survives a callback round-trip', () {
    // Arrange
    final Uri callback = Uri.parse(
      '/callback?returnTo=${Uri.encodeComponent('/a/b?x=1')}',
    );

    // Act
    final Uri resolved = ReturnTo.continueFrom(
      callback,
      fallback: Uri.parse('/home'),
    );

    // Assert
    expect(resolved.toString(), '/a/b?x=1');
  });

  test('falls back when the returnTo is absent or tampered', () {
    // Arrange
    final Uri fallback = Uri.parse('/home');

    // Assert
    expect(
      ReturnTo.continueFrom(Uri.parse('/callback'), fallback: fallback),
      fallback,
    );
    expect(
      ReturnTo.continueFrom(
        Uri.parse('/callback?returnTo=${Uri.encodeComponent('//evil')}'),
        fallback: fallback,
      ),
      fallback,
    );
  });
}
