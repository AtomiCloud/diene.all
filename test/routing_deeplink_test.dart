import 'package:diene_flutter_base/routing/deeplink.dart';
import 'package:diene_flutter_base/routing/route_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Config for a test build. Both values are supplied here the same way the app
/// supplies them from the config chain — nothing per-instance is written into
/// `lib/` (R4).
final DeeplinkConfig _config = DeeplinkConfig(
  webOrigin: Uri.parse('https://app.platform.example'),
  customScheme: 'cloud.example.platform.service.app',
  additionalWebOrigins: <Uri>[Uri.parse('https://vanity.example')],
);

final DeeplinkTranslator _translator = DeeplinkTranslator(config: _config);

void main() {
  group('authorityOf', () {
    test('lower-cases and strips the port', () {
      expect(
        authorityOf(Uri.parse('https://App.Example:8443/x')),
        'app.example',
      );
    });

    test('is empty for a URI with no authority', () {
      expect(authorityOf(Uri.parse('scheme:///home')), isEmpty);
    });
  });

  group('web link to app location (incoming, both platforms)', () {
    // Translation is platform-independent: which document authorized the
    // address (assetlinks.json on Android, AASA on iOS) is a build-time
    // concern, so the same accepted link resolves identically for both. Running
    // both platforms explicitly keeps the app↔web claim honest for each.
    for (final DeeplinkPlatform platform in DeeplinkPlatform.values) {
      for (final (String incoming, String expected) in <(String, String)>[
        ('https://app.platform.example/', '/home'),
        ('https://app.platform.example/onboarding', '/onboarding'),
        ('https://app.platform.example/finish', '/onboarding/finish'),
        ('https://app.platform.example/profile', '/profile'),
        ('https://app.platform.example/settings', '/settings'),
      ]) {
        test('${platform.wire}: "$incoming" resolves to "$expected"', () {
          final DeeplinkResolution resolution = _translator.resolve(
            Uri.parse(incoming),
          );

          expect(resolution, isA<DeeplinkAccepted>());
          expect((resolution as DeeplinkAccepted).location, expected);
        });
      }
    }

    test('carries the query through untouched', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse(
          'https://app.platform.example/settings?tab=security&q=two%20words',
        ),
      );

      // A deeplink that loses its query is a broken deeplink. Assert on the
      // printed value, not merely on acceptance.
      expect(
        (resolution as DeeplinkAccepted).location,
        '/settings?tab=security&q=two%20words',
      );
    });

    test('carries the fragment through untouched', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('https://app.platform.example/profile#tokens'),
      );

      expect((resolution as DeeplinkAccepted).location, '/profile#tokens');
    });

    test('reports which route matched', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('https://app.platform.example/finish'),
      );

      expect((resolution as DeeplinkAccepted).route.id, RouteIds.finish);
    });

    test('accepts an additional configured origin', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('https://vanity.example/profile'),
      );

      expect((resolution as DeeplinkAccepted).location, '/profile');
    });

    test('accepts the origin case-insensitively', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('https://APP.PLATFORM.EXAMPLE/profile'),
      );

      expect(resolution, isA<DeeplinkAccepted>());
    });
  });

  group('incoming links that must be refused', () {
    // The two refusals are DIFFERENT answers and the code keeps them apart: an
    // unmapped path on our own origin is a route-map defect worth fixing, a
    // foreign origin is a link that was never ours. Collapsing them would hide
    // the first behind the second.
    test('a foreign origin is refused as foreignOrigin', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('https://evil.test/profile'),
      );

      expect(
        (resolution as DeeplinkRejected).reason,
        DeeplinkRejection.foreignOrigin,
      );
    });

    test('a mismatched scheme on our own address is refused', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('http://app.platform.example/profile'),
      );

      expect(
        (resolution as DeeplinkRejected).reason,
        DeeplinkRejection.foreignOrigin,
      );
    });

    test('an unmapped path on our origin is refused as unmappedPath', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('https://app.platform.example/not-a-route'),
      );

      expect(
        (resolution as DeeplinkRejected).reason,
        DeeplinkRejection.unmappedPath,
      );
    });

    test('an unmapped custom-scheme path is refused as unmappedPath', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('cloud.example.platform.service.app:///nowhere'),
      );

      expect(
        (resolution as DeeplinkRejected).reason,
        DeeplinkRejection.unmappedPath,
      );
    });
  });

  group('custom-scheme links', () {
    test('a scheme link with an empty authority resolves', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('cloud.example.platform.service.app:///onboarding/finish'),
      );

      expect((resolution as DeeplinkAccepted).location, '/onboarding/finish');
    });

    test('a scheme link whose first segment parsed as authority resolves', () {
      // `scheme://profile` puts "profile" in the authority component, not the
      // path. Without rebuilding the path from both parts this silently becomes
      // an empty path and every such link dies.
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse('cloud.example.platform.service.app://profile'),
      );

      expect((resolution as DeeplinkAccepted).location, '/profile');
    });

    test('a scheme link keeps its query', () {
      final DeeplinkResolution resolution = _translator.resolve(
        Uri.parse(
          'cloud.example.platform.service.app:///settings?tab=security',
        ),
      );

      expect(
        (resolution as DeeplinkAccepted).location,
        '/settings?tab=security',
      );
    });
  });

  group('app location to shareable web URL (outgoing)', () {
    for (final (String location, String expected) in <(String, String)>[
      ('/home', 'https://app.platform.example/'),
      ('/onboarding', 'https://app.platform.example/onboarding'),
      ('/onboarding/finish', 'https://app.platform.example/finish'),
      ('/profile', 'https://app.platform.example/profile'),
      ('/settings', 'https://app.platform.example/settings'),
    ]) {
      test('"$location" shares as "$expected"', () {
        expect(_translator.toWebUri(location)?.toString(), expected);
      });
    }

    test('a query built up in the app survives into the shared URL', () {
      expect(
        _translator.toWebUri('/settings?tab=security&sort=newest')?.toString(),
        'https://app.platform.example/settings?tab=security&sort=newest',
      );
    });

    test('returns null for an unmapped app location', () {
      expect(_translator.toWebUri('/nowhere'), isNull);
    });

    test('builds a custom-scheme URL for a mapped location', () {
      expect(
        _translator.toSchemeUri('/onboarding/finish')?.toString(),
        'cloud.example.platform.service.app:///onboarding/finish',
      );
    });

    test('the custom-scheme URL keeps the query', () {
      expect(
        _translator.toSchemeUri('/settings?tab=security')?.toString(),
        'cloud.example.platform.service.app:///settings?tab=security',
      );
    });

    test('returns null for an unmapped scheme location', () {
      expect(_translator.toSchemeUri('/nowhere'), isNull);
    });
  });

  group('both directions compose for every shipped route', () {
    // This is the app↔web BOTH DIRECTIONS claim, asserted over the real map
    // rather than a sample: every route survives app → web → app unchanged.
    for (final DeeplinkRoute route in deeplinkRoutes) {
      test('${route.id} round-trips app to web and back', () {
        expect(
          _translator.roundTrips(route.app),
          isTrue,
          reason: 'round trip failed for ${route.id}',
        );
      });
    }

    test('a location with query round-trips including its query', () {
      expect(
        _translator.roundTrips('/settings?tab=security&sort=newest'),
        isTrue,
      );
    });

    test('roundTrips is false for an unmapped location', () {
      // Proves the round-trip check can answer NO — a predicate that only ever
      // returns true is not a check.
      expect(_translator.roundTrips('/nowhere'), isFalse);
    });

    test('every scheme URL round-trips back to its location', () {
      for (final DeeplinkRoute route in deeplinkRoutes) {
        final Uri? scheme = _translator.toSchemeUri(route.app);
        expect(scheme, isNotNull, reason: 'no scheme URL for ${route.id}');
        final DeeplinkResolution back = _translator.resolve(scheme!);
        expect(
          (back as DeeplinkAccepted).location,
          route.app,
          reason: 'scheme round trip failed for ${route.id}',
        );
      }
    });
  });

  group('returnTo round trip', () {
    for (final (String label, String intended) in <(String, String)>[
      ('a bare path', '/profile'),
      ('a path with a query string', '/settings?tab=security'),
      ('a path with multiple params', '/settings?q=milk&sort=due'),
      ('a path with an encoded space', '/settings?q=two%20words'),
      ('a nested path', '/onboarding/finish'),
    ]) {
      test('carries $label through login and back', () {
        final String login = buildLoginLocation('/login', intended);
        final String? raw = returnToOf(login);

        expect(login, startsWith('/login?'));
        expect(resolveReturnTo(raw), intended);
        expect(continueTo(raw), intended);
      });
    }

    test('appends to a login path that already has a query', () {
      final String login = buildLoginLocation(
        '/login?flow=deferred',
        '/profile',
      );

      expect(login, '/login?flow=deferred&returnTo=%2Fprofile');
      expect(resolveReturnTo(returnToOf(login)), '/profile');
    });

    test('keeps a fragment on the login path after the query', () {
      final String login = buildLoginLocation('/login#top', '/profile');

      expect(login, '/login?returnTo=%2Fprofile#top');
    });
  });

  group('returnTo fails closed', () {
    // An open redirect is a security defect, so each of these must be REFUSED
    // rather than followed. Every case is a value an attacker would actually
    // try, and the naive "starts with /" check passes two of them.
    for (final (String label, String raw) in <(String, String)>[
      ('an absolute URL to another origin', 'https://evil.test/steal'),
      ('a protocol-relative URL', '//evil.test/steal'),
      ('a backslash-relative URL', r'/\evil.test/steal'),
      ('a scheme instead of a path', 'javascript:alert(1)'),
      ('a bare relative path', 'profile'),
      ('an empty string', ''),
      ('a value with a newline', '/profile\nSet-Cookie: x=1'),
      ('a value with a carriage return', '/profile\rSet-Cookie: x=1'),
    ]) {
      test('rejects $label', () {
        expect(resolveReturnTo(raw), isNull, reason: 'should refuse: $raw');
      });
    }

    test('rejects a null value', () {
      expect(resolveReturnTo(null), isNull);
    });

    test('continueTo substitutes the fallback for a rejected value', () {
      expect(continueTo('https://evil.test/steal'), '/home');
    });

    test('continueTo honours a safe custom fallback', () {
      expect(continueTo(null, fallback: '/onboarding'), '/onboarding');
    });

    test('continueTo refuses an unsafe fallback too', () {
      // A caller passing a bad fallback must not create the hole the resolver
      // just closed.
      expect(continueTo(null, fallback: 'https://evil.test'), '/home');
    });
  });
}
