import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

ErrorPortal _portal({
  String scheme = 'https',
  String host = 'docs.raichu.cluster.atomi.cloud',
  String landscape = 'raichu',
  String platform = 'dotnet',
  String service = 'user',
  String module = 'api',
}) =>
    ErrorPortal(
      scheme: scheme,
      host: host,
      landscape: landscape,
      platform: platform,
      service: service,
      module: module,
    );

void main() {
  group('problemTypeUri', () {
    test('builds the full C0 §2 template with every LPSM segment', () {
      // Arrange
      final portal = _portal();
      // Act
      final uri = problemTypeUri(portal: portal, version: 'v1', id: 'entity-not-found');
      // Assert
      expect(
        uri,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity-not-found',
      );
    });

    test('places {version} and {id} as the final two segments', () {
      final uri = problemTypeUri(
        portal: _portal(landscape: 'pichu', platform: 'go', service: 'billing', module: 'svc'),
        version: 'v3',
        id: 'payment-declined',
      );
      expect(uri, endsWith('/billing/svc/v3/payment-declined'));
    });

    test('honours a custom scheme and host', () {
      final uri = problemTypeUri(
        portal: _portal(scheme: 'http', host: 'localhost:8080'),
        version: 'v1',
        id: 'x',
      );
      expect(uri, startsWith('http://localhost:8080/docs/'));
    });

    test('rejects an empty segment', () {
      expect(
        () => problemTypeUri(portal: _portal(landscape: ''), version: 'v1', id: 'x'),
        throwsA(isA<InvalidProblemTypeSegmentError>()),
      );
    });

    test('rejects a segment containing a slash', () {
      expect(
        () => problemTypeUri(portal: _portal(platform: 'a/b'), version: 'v1', id: 'x'),
        throwsA(isA<InvalidProblemTypeSegmentError>()),
      );
      expect(
        () => problemTypeUri(portal: _portal(), version: 'v1', id: 'has/slash'),
        throwsA(isA<InvalidProblemTypeSegmentError>()),
      );
    });

    test('rejects an empty version', () {
      expect(
        () => problemTypeUri(portal: _portal(), version: '', id: 'x'),
        throwsA(isA<InvalidProblemTypeSegmentError>()),
      );
    });

    test('ErrorPortal.localError is a usable fallback portal', () {
      final uri = problemTypeUri(
        portal: ErrorPortal.localError,
        version: 'v1',
        id: 'local-error',
      );
      expect(uri, 'https://local.atomi.cloud/docs/local/flutter/app/core/v1/local-error');
    });
  });
}
