import 'package:diene_problems/diene_problems.dart';
import 'package:test/test.dart';

ErrorPortal _portal({
  String scheme = 'https',
  String host = 'docs.raichu.cluster.atomi.cloud',
  String landscape = 'raichu',
  String platform = 'dotnet',
  String service = 'user',
  String module = 'api',
}) => ErrorPortal(
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
      final uri = problemTypeUri(
        portal: portal,
        version: 'v1',
        id: 'entity_not_found',
      );
      // Assert
      expect(
        uri,
        'https://docs.raichu.cluster.atomi.cloud/docs/raichu/dotnet/user/api/v1/entity_not_found',
      );
    });

    test('places {version} and {id} as the final two segments', () {
      final uri = problemTypeUri(
        portal: _portal(
          landscape: 'pichu',
          platform: 'go',
          service: 'billing',
          module: 'svc',
        ),
        version: 'v3',
        id: 'payment_declined',
      );
      expect(uri, endsWith('/billing/svc/v3/payment_declined'));
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
        () => problemTypeUri(
          portal: _portal(landscape: ''),
          version: 'v1',
          id: 'x',
        ),
        throwsA(isA<InvalidProblemTypeSegmentError>()),
      );
    });

    test('rejects a segment containing a slash', () {
      expect(
        () => problemTypeUri(
          portal: _portal(platform: 'a/b'),
          version: 'v1',
          id: 'x',
        ),
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
        id: 'local_error',
      );
      expect(
        uri,
        'https://local.atomi.cloud/docs/local/flutter/app/core/v1/local_error',
      );
    });

    test('accepts a host:port authority', () {
      // Arrange
      final portal = _portal(scheme: 'http', host: 'localhost:8080');
      // Act
      final uri = problemTypeUri(portal: portal, version: 'v2', id: 'boom');
      // Assert
      expect(uri, startsWith('http://localhost:8080/docs/'));
      expect(uri, endsWith('/v2/boom'));
    });

    test('rejects a host that is not a bare authority', () {
      // A doc-sourced portal is untrusted input, so anything carrying URL
      // components, whitespace, or credentials is refused at the boundary
      // rather than silently producing a malformed type URI.
      for (final host in <String>[
        '', // empty
        ' docs.atomi.cloud', // leading space
        'docs.atomi.cloud ', // trailing space
        'docs.atomi.cloud/docs', // path component
        r'docs.atomi.cloud\docs', // backslash
        'docs atomi cloud', // inner whitespace
        'user@docs.atomi.cloud', // credentials
        'docs.atomi.cloud?a=b', // query
        'docs.atomi.cloud#frag', // fragment
      ]) {
        expect(
          () => problemTypeUri(
            portal: _portal(host: host),
            version: 'v1',
            id: 'entity_not_found',
          ),
          throwsA(isA<InvalidProblemTypeSegmentError>()),
          reason: 'host <$host> must be rejected',
        );
      }
    });

    test('rejects a host whose parsed authority is not canonical', () {
      // Uppercase authorities normalise on parse, so the parsed origin no
      // longer equals the configured host — a misconfiguration worth failing
      // loudly instead of emitting two different URIs for one problem.
      expect(
        () => problemTypeUri(
          portal: _portal(host: 'DOCS.Atomi.Cloud'),
          version: 'v1',
          id: 'entity_not_found',
        ),
        throwsA(isA<InvalidProblemTypeSegmentError>()),
      );
    });

    test('rejects a version outside the v<n> shape', () {
      for (final version in <String>['1', 'V1', 'v', 'v1.2', 'latest']) {
        expect(
          () => problemTypeUri(
            portal: _portal(),
            version: version,
            id: 'entity_not_found',
          ),
          throwsA(isA<InvalidProblemTypeSegmentError>()),
          reason: 'version <$version> must be rejected',
        );
      }
    });

    test('rejects a wire id that is not snake_case (R-E14)', () {
      for (final id in <String>[
        'entity-not-found',
        'EntityNotFound',
        'entity.not.found',
        '1entity',
        '_entity',
      ]) {
        expect(
          () => problemTypeUri(portal: _portal(), version: 'v1', id: id),
          throwsA(isA<InvalidProblemTypeSegmentError>()),
          reason: 'id <$id> must be rejected',
        );
      }
    });

    test('names the offending segment on rejection', () {
      // Arrange / Act
      Object? thrown;
      try {
        problemTypeUri(portal: _portal(), version: 'v1', id: 'BAD');
      } on InvalidProblemTypeSegmentError catch (error) {
        thrown = error;
      }
      // Assert
      expect(thrown, isA<InvalidProblemTypeSegmentError>());
      expect((thrown! as InvalidProblemTypeSegmentError).name, 'id');
    });
  });

  group('r14WireId', () {
    test('rewrites kebab to snake and leaves conforming ids alone', () {
      expect(r14WireId('entity-not-found'), 'entity_not_found');
      expect(r14WireId('app-handoff-expired'), 'app_handoff_expired');
      expect(r14WireId('already_snake'), 'already_snake');
    });
  });
}
