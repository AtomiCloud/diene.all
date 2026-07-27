import 'dart:io';

import 'package:diene_flutter_base/routing/route_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// The counterpart the route-map format is a contract WITH, pinned by blob so a
/// revision on the web track is a detectable event rather than silent drift.
/// See the dartdoc block in `lib/routing/route_map.dart`.
const String _counterpartPath = 'src/lib/deeplink/route-map.ts';
const String _counterpartBlob = '8fab918db8d9c1ea0d44a62651700890243e9390';
const String _counterpartCommit = '889850b1922ce13f8b1d606974d11fe7e96fb69c';
const String _counterpartRef = 'authoritative/nextjs-frontend';

void main() {
  group('route map validity', () {
    test('the shipped map is a well-formed invertible mapping', () {
      final List<String> errors = validateRouteMap(deeplinkRoutes);

      expect(errors, isEmpty, reason: 'shipped map must validate: $errors');
    });

    test('every entry declares a non-empty id, web and app pattern', () {
      for (final DeeplinkRoute route in deeplinkRoutes) {
        expect(route.id, isNotEmpty);
        expect(route.web, isNotEmpty);
        expect(route.app, isNotEmpty);
      }
    });

    // The frozen table. This is the LOCAL half of the cross-track pin: editing
    // `deeplinkRoutes` without re-pinning the counterpart blob turns this red,
    // so the two maps cannot drift apart from this side unnoticed.
    test('the shipped table is exactly the pinned five triples', () {
      expect(deeplinkRoutes, <DeeplinkRoute>[
        const DeeplinkRoute(id: 'home', web: '/', app: '/home'),
        const DeeplinkRoute(
          id: 'onboarding',
          web: '/onboarding',
          app: '/onboarding',
        ),
        const DeeplinkRoute(
          id: 'finish',
          web: '/finish',
          app: '/onboarding/finish',
        ),
        const DeeplinkRoute(id: 'profile', web: '/profile', app: '/profile'),
        const DeeplinkRoute(id: 'settings', web: '/settings', app: '/settings'),
      ]);
    });
  });

  group('route map validation catches malformed tables', () {
    // Each case below is a table that LOOKS reasonable and is not. A validator
    // that has never failed is indistinguishable from one that cannot fail, so
    // every rule gets a knowingly-bad input.

    test('a duplicate id is rejected', () {
      final List<String> errors = validateRouteMap(<DeeplinkRoute>[
        const DeeplinkRoute(id: 'a', web: '/a', app: '/app/a'),
        const DeeplinkRoute(id: 'a', web: '/b', app: '/app/b'),
      ]);

      expect(errors, contains('duplicate id: a'));
    });

    test('a duplicate web pattern is rejected', () {
      final List<String> errors = validateRouteMap(<DeeplinkRoute>[
        const DeeplinkRoute(id: 'a', web: '/same', app: '/app/a'),
        const DeeplinkRoute(id: 'b', web: '/same', app: '/app/b'),
      ]);

      expect(errors, contains('duplicate web pattern: /same'));
    });

    test('a duplicate app pattern is rejected', () {
      final List<String> errors = validateRouteMap(<DeeplinkRoute>[
        const DeeplinkRoute(id: 'a', web: '/a', app: '/same'),
        const DeeplinkRoute(id: 'b', web: '/b', app: '/same'),
      ]);

      expect(errors, contains('duplicate app pattern: /same'));
    });

    test('an asymmetric parameter set is rejected', () {
      // The sabotage the gate exists for: a web pattern with no parameter
      // against an app pattern that needs one is a link the app cannot resolve,
      // and it reads as a perfectly ordinary row until both sides are compared.
      final List<String> errors = validateRouteMap(<DeeplinkRoute>[
        const DeeplinkRoute(id: 'edit', web: '/edit', app: '/edit/:id'),
      ]);

      expect(errors.single, 'param mismatch on edit: web() app(id)');
    });

    test('a renamed parameter is rejected even when the count matches', () {
      final List<String> errors = validateRouteMap(<DeeplinkRoute>[
        const DeeplinkRoute(
          id: 'signal',
          web: '/signal/:id',
          app: '/signal/:signalId',
        ),
      ]);

      expect(errors, hasLength(1));
      expect(errors.single, contains('param mismatch on signal'));
    });

    test('an unrooted pattern is rejected', () {
      final List<String> errors = validateRouteMap(<DeeplinkRoute>[
        const DeeplinkRoute(id: 'loose', web: 'loose', app: 'loose'),
      ]);

      expect(errors, hasLength(2));
      expect(errors, contains('web pattern is not rooted on loose: loose'));
      expect(errors, contains('app pattern is not rooted on loose: loose'));
    });

    test('a segment mixing a placeholder with literal text is rejected', () {
      final List<String> errors = validateRouteMap(<DeeplinkRoute>[
        const DeeplinkRoute(
          id: 'mixed',
          web: '/signal-:id',
          app: '/signal-:id',
        ),
      ]);

      expect(
        errors.where((String error) => error.contains('mixes a placeholder')),
        hasLength(2),
      );
    });

    test('adding one unmapped route turns the shipped map red', () {
      // The E4 matrix's named sabotage for this gate, run as a positive case so
      // the check is proven able to go RED against the real table rather than
      // only against a synthetic one.
      final List<DeeplinkRoute> sabotaged = <DeeplinkRoute>[
        ...deeplinkRoutes,
        const DeeplinkRoute(id: 'orphan', web: '/orphan', app: '/orphan/:id'),
      ];

      final List<String> errors = validateRouteMap(sabotaged);

      expect(errors, isNotEmpty);
      expect(errors.single, contains('param mismatch on orphan'));
    });
  });

  group('web to app', () {
    for (final (String path, String expected) in <(String, String)>[
      ('/', '/home'),
      ('/onboarding', '/onboarding'),
      ('/finish', '/onboarding/finish'),
      ('/profile', '/profile'),
      ('/settings', '/settings'),
    ]) {
      test('maps web "$path" to app "$expected"', () {
        expect(webToApp(path), expected);
      });
    }

    test('returns null for an unmapped web path', () {
      // "Found nothing" must not look like "could not look": an unmapped path
      // is null, never a silent fallback to home.
      expect(webToApp('/not-a-route'), isNull);
    });

    test('does not confuse a deeper path for a shorter pattern', () {
      expect(webToApp('/profile/security'), isNull);
    });

    test('substitutes a captured path parameter', () {
      const List<DeeplinkRoute> routes = <DeeplinkRoute>[
        DeeplinkRoute(id: 'signal', web: '/s/:id', app: '/signal/:id'),
      ];

      expect(webToApp('/s/42', routes: routes), '/signal/42');
    });
  });

  group('app to web', () {
    for (final (String path, String expected) in <(String, String)>[
      ('/home', '/'),
      ('/onboarding', '/onboarding'),
      ('/onboarding/finish', '/finish'),
      ('/profile', '/profile'),
      ('/settings', '/settings'),
    ]) {
      test('maps app "$path" to web "$expected"', () {
        expect(appToWeb(path), expected);
      });
    }

    test('returns null for an unmapped app route', () {
      expect(appToWeb('/nowhere'), isNull);
    });

    test('substitutes a captured path parameter', () {
      const List<DeeplinkRoute> routes = <DeeplinkRoute>[
        DeeplinkRoute(id: 'signal', web: '/s/:id', app: '/signal/:id'),
      ];

      expect(appToWeb('/signal/42', routes: routes), '/s/42');
    });
  });

  group('both directions compose', () {
    test('every entry round-trips web to app and back', () {
      for (final DeeplinkRoute route in deeplinkRoutes) {
        final String? app = webToApp(route.web);
        expect(app, route.app, reason: 'web->app for ${route.id}');
        expect(appToWeb(app!), route.web, reason: 'app->web for ${route.id}');
      }
    });

    test('every entry round-trips app to web and back', () {
      for (final DeeplinkRoute route in deeplinkRoutes) {
        final String? web = appToWeb(route.app);
        expect(web, route.web, reason: 'app->web for ${route.id}');
        expect(webToApp(web!), route.app, reason: 'web->app for ${route.id}');
      }
    });
  });

  group('lookups', () {
    test('routeById finds every shipped id', () {
      for (final DeeplinkRoute route in deeplinkRoutes) {
        expect(routeById(route.id), route);
      }
    });

    test('routeById returns null for an unknown id', () {
      expect(routeById('no-such-screen'), isNull);
    });

    test('routeForAppPath resolves a concrete app path to its entry', () {
      expect(routeForAppPath('/onboarding/finish')?.id, RouteIds.finish);
      expect(routeForAppPath('/nowhere'), isNull);
    });

    test('routeParameters reads placeholders in declaration order', () {
      expect(routeParameters('/a/:first/b/:second'), <String>[
        'first',
        'second',
      ]);
      expect(routeParameters('/static'), isEmpty);
    });
  });

  // The REMOTE half of the cross-track pin. The frozen-table test above stops
  // this side drifting; this stops the counterpart drifting unnoticed. It is
  // conditional on the counterpart being reachable, because a Flutter unit test
  // must pass on a machine that has only this repo checked out — but the two
  // outcomes are kept distinguishable: a MISSING counterpart skips with a
  // printed reason, while a PRESENT-BUT-CHANGED counterpart fails. "Could not
  // look" and "looked and it moved" must never produce the same answer.
  group('cross-track counterpart pin', () {
    test('the pinned counterpart blob still matches, when reachable', () {
      final ProcessResult probe = Process.runSync('git', <String>[
        'rev-parse',
        '--verify',
        '--quiet',
        _counterpartRef,
      ]);
      if (probe.exitCode != 0) {
        printOnFailure('ref $_counterpartRef unreachable');
        markTestSkipped(
          'counterpart ref $_counterpartRef is not present in this checkout; '
          'the pin is recorded but UNVERIFIED here (blob $_counterpartBlob '
          'at commit $_counterpartCommit)',
        );
        return;
      }

      final ProcessResult listed = Process.runSync('git', <String>[
        'ls-tree',
        _counterpartRef,
        '--',
        _counterpartPath,
      ]);
      expect(
        listed.exitCode,
        0,
        reason: 'git ls-tree failed: ${listed.stderr}',
      );
      final String output = (listed.stdout as String).trim();
      if (output.isEmpty) {
        markTestSkipped(
          'counterpart $_counterpartPath is absent from $_counterpartRef; '
          'the pin is recorded but UNVERIFIED here',
        );
        return;
      }

      // Format: "<mode> blob <sha>\t<path>".
      final String actualBlob = output.split(RegExp(r'\s+'))[2];
      expect(
        actualBlob,
        _counterpartBlob,
        reason:
            'The web track revised $_counterpartPath. The route-map format is '
            'a cross-track CONTRACT and the literal-comparison property is '
            'now broken. Diff the counterpart against lib/routing/route_map.dart, '
            'reconcile the tables, then re-pin the blob in BOTH that file and '
            'this test. Pinned $_counterpartBlob (commit $_counterpartCommit), '
            'found $actualBlob.',
      );
    });
  });
}
