import 'package:diene_api_engine/diene_api_engine.dart';
import 'package:diene_api_engine/test_helper.dart';
import 'package:test/test.dart';

HttpRequest _req() => HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('https://api.example.com/ping'),
    );

void main() {
  group('RetryOnceTransport', () {
    test('retries exactly once on a network failure, then succeeds', () async {
      // Arrange
      final FakeHttpTransport inner = FakeHttpTransport.sequence(
        <TransportOutcome>[networkFailure(), okJson(<String, Object?>{})],
      );
      final RetryOnceTransport transport = RetryOnceTransport(inner);

      // Act
      final TransportOutcome outcome = await transport.send(_req());

      // Assert
      expect(outcome, isA<Received>());
      expect(inner.callCount, 2);
    });

    test('surfaces a hard failure after exactly two network failures',
        () async {
      final FakeHttpTransport inner = FakeHttpTransport.sequence(
        <TransportOutcome>[networkFailure(), networkFailure()],
      );
      final TransportOutcome outcome =
          await RetryOnceTransport(inner).send(_req());
      expect(outcome, isA<NetworkFailure>());
      expect(inner.callCount, 2);
    });

    test('never retries a received status, even 5xx', () async {
      final FakeHttpTransport inner = FakeHttpTransport.sequence(
        <TransportOutcome>[nonJsonResponse(status: 500)],
      );
      final TransportOutcome outcome =
          await RetryOnceTransport(inner).send(_req());
      expect(outcome, isA<Received>());
      expect(inner.callCount, 1);
    });
  });
}
