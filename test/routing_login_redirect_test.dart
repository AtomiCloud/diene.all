import 'package:diene_auth_engine/diene_auth_engine.dart' as engine;
import 'package:diene_flutter_base/app.dart';
import 'package:diene_flutter_base/auth/session_controller.dart';
import 'package:diene_flutter_base/config/app_config.dart';
import 'package:diene_flutter_base/config/app_settings_controller.dart';
import 'package:diene_flutter_base/i18n/translations.g.dart';
import 'package:diene_flutter_base/onboarding/onboarding.dart';
import 'package:diene_flutter_base/routing/app_router.dart';
import 'package:diene_flutter_base/routing/deeplink.dart';
import 'package:diene_flutter_base/routing/query_state.dart';
import 'package:diene_flutter_base/routing/route_map.dart';
import 'package:diene_flutter_base/screens/app_screens.dart';
import 'package:diene_flutter_base/screens/login_screen.dart';
import 'package:diene_flutter_base/screens/screen_registry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

/// A screen that is deliberately NOT in the route map, used to prove the
/// route-for-every-screen check can go RED. Declared here rather than in `lib/`
/// so the shipped registry stays correct while the check is still exercised
/// against a real violation.
final ScreenDefinition _screenWithoutRoute = ScreenDefinition(
  routeId: 'reports',
  title: 'Reports',
  builder: (BuildContext context, ScreenRouteContext route) =>
      const SizedBox.shrink(),
);

void main() {
  // Referenced so the config helper stays the shared one; the routing surface
  // itself takes no AppConfig.
  setUpAll(() => testConfig());

  group('route-for-every-screen', () {
    test('every shipped screen has a route-map entry', () {
      final List<ScreenDefinition> orphans = screensWithoutRoutes();

      expect(
        orphans,
        isEmpty,
        reason:
            'these screens cannot be reached by any link: '
            '${orphans.map((ScreenDefinition s) => s.routeId).join(', ')}',
      );
    });

    test('declared screen ids are a SUBSET of the route map ids', () {
      // The subset direction is the one the E4 matrix names. The map may
      // legitimately carry a path the app does not render; the app may never
      // render a destination the map does not carry.
      final Set<String> mapIds = deeplinkRoutes
          .map((DeeplinkRoute route) => route.id)
          .toSet();

      expect(declaredScreenIds(), _isSubsetOf(mapIds));
    });

    test('every screen resolves to the app path its route declares', () {
      for (final ScreenDefinition screen in appScreens) {
        expect(
          pathForScreen(screen.routeId),
          routeById(screen.routeId)!.app,
          reason: 'path mismatch for ${screen.routeId}',
        );
      }
    });

    test('no two screens claim the same route id', () {
      final List<String> ids = appScreens
          .map((ScreenDefinition screen) => screen.routeId)
          .toList();

      expect(ids.toSet().length, ids.length, reason: 'duplicate screen ids');
    });

    // === The gate proven able to go RED =====================================
    // A screen added WITHOUT a route is the E4 matrix's named sabotage. Running
    // it here means the check has demonstrably failed at least once, so a green
    // from it is worth something.

    test('a screen without a route is REPORTED, not silently accepted', () {
      final List<ScreenDefinition> withOrphan = <ScreenDefinition>[
        ...appScreens,
        _screenWithoutRoute,
      ];

      final List<ScreenDefinition> orphans = screensWithoutRoutes(withOrphan);

      expect(orphans, hasLength(1));
      expect(orphans.single.routeId, 'reports');
    });

    test('a screen without a route breaks the subset property', () {
      final Set<String> mapIds = deeplinkRoutes
          .map((DeeplinkRoute route) => route.id)
          .toSet();
      final List<ScreenDefinition> withOrphan = <ScreenDefinition>[
        ...appScreens,
        _screenWithoutRoute,
      ];

      expect(declaredScreenIds(withOrphan), isNot(_isSubsetOf(mapIds)));
    });

    test('a screen without a route cannot be given a path', () {
      // Not merely reported — unusable. Inventing a path would ship a
      // destination no link can reach, which is worse than a loud failure.
      expect(() => pathForScreen('reports'), throwsA(isA<StateError>()));
    });

    test('building a router over an unrouted screen throws', () {
      expect(
        () => buildAppRouter(
          isAuthenticated: () => false,
          loginBuilder: _loginBuilder,
          screens: <ScreenDefinition>[...appScreens, _screenWithoutRoute],
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('protected screens are the ones declared protected', () {
    test('the registry marks exactly the expected screens protected', () {
      final Set<String> protected = appScreens
          .where((ScreenDefinition screen) => screen.protected)
          .map((ScreenDefinition screen) => screen.routeId)
          .toSet();

      expect(protected, protectedScreenIds);
    });

    test('home and onboarding stay reachable unauthenticated', () {
      // A gate that protects everything is not a gate, it is a wall: sign-in
      // itself must remain reachable.
      for (final String id in <String>[ScreenIds.home, ScreenIds.onboarding]) {
        expect(
          redirectFor(location: pathForScreen(id), isAuthenticated: false),
          isNull,
          reason: '$id must not require a session',
        );
      }
    });
  });

  group('login redirect return: the deeplink survives login', () {
    for (final (String label, String intended) in <(String, String)>[
      ('a bare protected path', '/profile'),
      ('a protected path with one query param', '/profile?tab=security'),
      (
        'a protected path with several params',
        '/settings?q=disk&sort=severity',
      ),
      ('a nested protected path', '/onboarding/finish'),
      ('a param with an encoded space', '/settings?q=two%20words'),
    ]) {
      test('$label is preserved through login and returned to', () {
        // 1. Unauthenticated hit on the protected deeplink.
        final String? redirect = redirectFor(
          location: intended,
          isAuthenticated: false,
        );

        expect(redirect, isNotNull, reason: 'should have redirected to login');
        expect(redirect, startsWith('$loginPath?'));

        // 2. The login location carries the WHOLE intended location.
        final String? carried = returnToOf(redirect!);
        expect(carried, intended, reason: 'path and query must both survive');

        // 3. After authentication, the router returns to it.
        final String? afterLogin = redirectFor(
          location: redirect,
          isAuthenticated: true,
        );
        expect(afterLogin, intended);
      });
    }

    test('the query state itself survives the whole journey', () {
      // The end-to-end claim: the FILTERS a viewer deeplinked with are the
      // filters they see after signing in, not just some path.
      const SignalQuery intendedState = SignalQuery(
        text: 'disk pressure',
        severities: <SignalSeverity>[SignalSeverity.critical],
        sort: SignalSort.severityFirst,
        page: 2,
      );
      final String intended = intendedState.toLocation('/settings');

      final String redirect = redirectFor(
        location: intended,
        isAuthenticated: false,
      )!;
      final String returned = redirectFor(
        location: redirect,
        isAuthenticated: true,
      )!;

      expect(
        SignalQuery.fromQueryParameters(Uri.parse(returned).queryParameters),
        intendedState,
      );
    });

    test('an authenticated hit on a protected route is not redirected', () {
      expect(
        redirectFor(location: '/profile?tab=security', isAuthenticated: true),
        isNull,
      );
    });

    test('an unauthenticated hit on the login route proceeds', () {
      expect(redirectFor(location: loginPath, isAuthenticated: false), isNull);
    });

    test('an unmapped location is not redirected to login', () {
      // A 404 is not an authorization failure; sending it to login would be a
      // confusing lie about what went wrong.
      expect(redirectFor(location: '/nowhere', isAuthenticated: false), isNull);
    });

    test('a web deeplink translates then redirects, preserving the query', () {
      // The full app↔web journey: an authorized web URL arrives, becomes an app
      // location, and THAT is what gets preserved through login.
      final DeeplinkTranslator translator = DeeplinkTranslator(
        config: DeeplinkConfig(
          webOrigin: Uri.parse('https://app.platform.example'),
          customScheme: 'cloud.example.platform.service.app',
        ),
      );

      final DeeplinkResolution resolution = translator.resolve(
        Uri.parse('https://app.platform.example/settings?q=disk&sort=severity'),
      );
      final String location = (resolution as DeeplinkAccepted).location;

      final String redirect = redirectFor(
        location: location,
        isAuthenticated: false,
      )!;

      expect(returnToOf(redirect), '/settings?q=disk&sort=severity');
      expect(redirectFor(location: redirect, isAuthenticated: true), location);
    });

    // === The gate proven able to go RED =====================================

    test('dropping the pending route loses the deeplink', () {
      // The E4 matrix's named sabotage for this gate: "drop the pending route".
      // A login redirect built WITHOUT returnTo typechecks perfectly and looks
      // like a working redirect — every deeplink just quietly lands on home.
      const String sabotaged = loginPath;

      expect(returnToOf(sabotaged), isNull);
      expect(
        continueTo(returnToOf(sabotaged)),
        '/home',
        reason: 'without returnTo the intended destination is unrecoverable',
      );
      // And it differs from the real behaviour, which is the point.
      expect(
        returnToOf(
          redirectFor(
            location: '/profile?tab=security',
            isAuthenticated: false,
          )!,
        ),
        '/profile?tab=security',
      );
    });

    test('carrying only the path loses the query', () {
      // The subtler sabotage: preserve the path but not the query. The redirect
      // works, the viewer lands on the right screen, and every filter is gone.
      final String pathOnly = buildLoginLocation(loginPath, '/settings');
      final String full = buildLoginLocation(
        loginPath,
        '/settings?q=disk&sort=severity',
      );

      expect(returnToOf(pathOnly), '/settings');
      expect(returnToOf(full), '/settings?q=disk&sort=severity');
      expect(returnToOf(pathOnly), isNot(returnToOf(full)));
    });
  });

  group('login redirect fails closed', () {
    for (final (String label, String raw) in <(String, String)>[
      ('an off-origin absolute URL', 'https://evil.test/steal'),
      ('a protocol-relative URL', '//evil.test/steal'),
      ('a backslash-relative URL', r'/\evil.test'),
      ('a scheme instead of a path', 'javascript:alert(1)'),
    ]) {
      test('an authenticated login hit with $label goes to a safe default', () {
        // An attacker-supplied returnTo must not become a redirect target: the
        // router substitutes the safe default rather than following it.
        final String location =
            '$loginPath?$returnToParameter=${Uri.encodeQueryComponent(raw)}';

        expect(redirectFor(location: location, isAuthenticated: true), '/home');
      });
    }
  });

  group('the router is wired to the checked redirect', () {
    // The pure function above is only worth testing if the shipped router
    // actually uses it. These assert the real GoRouter's behaviour.

    testWidgets('an unauthenticated protected deeplink lands on login', (
      WidgetTester tester,
    ) async {
      String? seenReturnTo;
      final GoRouter router = buildAppRouter(
        isAuthenticated: () => false,
        initialLocation: '/profile?tab=security',
        loginBuilder: (BuildContext context, String returnTo) {
          seenReturnTo = returnTo;
          return const _LoginStub();
        },
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      expect(find.byType(_LoginStub), findsOneWidget);
      // The login screen RECEIVES the full intended location, so W3's gate has
      // what it needs to return there.
      expect(seenReturnTo, '/profile?tab=security');
      expect(router.routerDelegate.currentConfiguration.uri.path, loginPath);
    });

    testWidgets('an authenticated protected deeplink renders the screen', (
      WidgetTester tester,
    ) async {
      final GoRouter router = buildAppRouter(
        isAuthenticated: () => true,
        initialLocation: '/profile?tab=security',
        loginBuilder: (BuildContext context, String returnTo) =>
            const _LoginStub(),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      expect(find.byType(_LoginStub), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);
      // Route parsing happened at the edge: the screen got the parsed value.
      expect(find.text('tab=security'), findsOneWidget);
    });

    testWidgets('an unauthenticated public deeplink renders the screen', (
      WidgetTester tester,
    ) async {
      final GoRouter router = buildAppRouter(
        isAuthenticated: () => false,
        initialLocation: '/onboarding',
        loginBuilder: (BuildContext context, String returnTo) =>
            const _LoginStub(),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingScreen), findsOneWidget);
    });

    testWidgets('every shipped screen is reachable by its own route', (
      WidgetTester tester,
    ) async {
      // route-for-every-screen, asserted by actually NAVIGATING rather than by
      // inspecting a list: a route that exists but cannot render is still a
      // broken destination.
      for (final ScreenDefinition screen in appScreens) {
        final GoRouter router = buildAppRouter(
          isAuthenticated: () => true,
          initialLocation: pathForScreen(screen.routeId),
          loginBuilder: (BuildContext context, String returnTo) =>
              const _LoginStub(),
        );

        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'rendering ${screen.routeId} threw',
        );
        expect(
          find.byType(_LoginStub),
          findsNothing,
          reason: '${screen.routeId} should render, not redirect',
        );
        router.dispose();
      }
    });

    testWidgets('url-as-state: the platform sees every filter change', (
      WidgetTester tester,
    ) async {
      // Back/forward correctness, asserted where it actually lives: the ROUTE
      // INFORMATION the router reports to the platform. `go` to the same path
      // with a new query replaces the top page rather than stacking one (so
      // `router.pop()` has nothing to pop and would throw) — the history entry
      // is created by the platform from the reported location, not by a Navigator
      // page. So the property to check is that each filter change is reported as
      // a distinct location, which is what gives the OS/browser something to go
      // back TO.
      final List<String> reported = <String>[];
      final GoRouter router = buildAppRouter(
        isAuthenticated: () => true,
        initialLocation: '/home?q=first',
        loginBuilder: (BuildContext context, String returnTo) =>
            const _LoginStub(),
      );
      addTearDown(router.dispose);
      void record() => reported.add(
        router.routerDelegate.currentConfiguration.uri.toString(),
      );
      router.routerDelegate.addListener(record);
      addTearDown(() => router.routerDelegate.removeListener(record));

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      router.go('/home?q=second');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.query, 'q=second');

      router.go('/home?q=third');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.query, 'q=third');

      // Every change surfaced as its own location: nothing was swallowed, which
      // is the failure mode that breaks Back.
      expect(
        reported,
        containsAllInOrder(<String>['/home?q=second', '/home?q=third']),
      );

      // And restoring an earlier location — what Back does — reproduces the
      // earlier state exactly.
      router.go('/home?q=first');
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.query, 'q=first');
      expect(find.text('text=first'), findsOneWidget);
    });

    testWidgets('a live search edit replaces rather than stacks history', (
      WidgetTester tester,
    ) async {
      // The search-bar standard's reason for `replace` over `push`: typing must
      // not push one history entry per keystroke. Asserted through the real
      // widget, so a change from replace to push in the search bar fails here.
      final GoRouter router = buildAppRouter(
        isAuthenticated: () => true,
        initialLocation: '/home',
        loginBuilder: (BuildContext context, String returnTo) =>
            const _LoginStub(),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      final Finder field = find.descendant(
        of: find.byType(SearchBar),
        matching: find.byType(EditableText),
      );
      await tester.enterText(field, 'disk');
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/home?q=disk',
      );
      // One page on the stack, not one per keystroke.
      expect(
        router.routerDelegate.currentConfiguration.matches.length,
        1,
        reason: 'live edits must replace, not push',
      );

      // Clearing removes the parameter entirely rather than leaving "?q=".
      await tester.enterText(field, '');
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/home',
      );
    });

    testWidgets('a shared link reproduces the state on screen', (
      WidgetTester tester,
    ) async {
      // The query-state gate, end to end through the real router: open the
      // shareable location and read the values the screen renders.
      const SignalQuery shared = SignalQuery(
        text: 'disk',
        severities: <SignalSeverity>[SignalSeverity.critical],
        sort: SignalSort.severityFirst,
        page: 2,
        unresolvedOnly: true,
      );
      final GoRouter router = buildAppRouter(
        isAuthenticated: () => true,
        initialLocation: shared.toLocation('/home'),
        loginBuilder: (BuildContext context, String returnTo) =>
            const _LoginStub(),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      expect(find.text('text=disk'), findsOneWidget);
      expect(find.text('severities=critical'), findsOneWidget);
      expect(find.text('sort=severity'), findsOneWidget);
      expect(find.text('page=2'), findsOneWidget);
      expect(find.text('unresolvedOnly=true'), findsOneWidget);
    });
  });

  group('the shipped app shell passes a real session check', () {
    // COVERAGE OF THE MOUNT, not of the router.
    //
    // Every other test in this file calls buildAppRouter directly and INJECTS
    // isAuthenticated, which tests the router correctly and cannot test the
    // ARGUMENT lib/app.dart passes it. That left the production wiring with no
    // coverage at all: `widget.session.tokens != null` could be inverted or
    // replaced with a constant and the whole suite stayed green — verified, a
    // `() => true` there passed all 330 tests.
    //
    // These two pump the REAL DieneApp so the assertion is about what ships. The
    // pair matters: the first alone would pass against a constant `false`, and
    // the second alone would pass against a constant `true`. Only both together
    // pin the value to the session.

    testWidgets('an unauthenticated shell sends a protected route to login', (
      WidgetTester tester,
    ) async {
      final _Shell shell = await _pumpShell(tester, authenticated: false);

      shell.router.go('/profile?tab=security');
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsNothing);
      // And the deeplink was preserved on the way, not merely blocked.
      expect(find.text('returnTo=/profile?tab=security'), findsOneWidget);
    });

    testWidgets('an authenticated shell renders the protected route', (
      WidgetTester tester,
    ) async {
      final _Shell shell = await _pumpShell(tester, authenticated: true);

      shell.router.go('/profile?tab=security');
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(find.text('tab=security'), findsOneWidget);
    });

    testWidgets('the shell still serves its own root route', (
      WidgetTester tester,
    ) async {
      // `/` is the inherited shell home and is deliberately NOT a registry
      // screen, so it must stay reachable and stay public.
      await _pumpShell(tester, authenticated: false);

      expect(find.byType(LoginScreen), findsNothing);
      expect(
        find.text('A calm control room for every landscape.'),
        findsOneWidget,
      );
    });
  });

  group('LoginScreen completes the return journey', () {
    // The shipped login screen, mounted through the real router: the redirect
    // carries returnTo here, and signing in continues to it. This is the half a
    // pure-function test cannot cover.

    testWidgets('signing in continues to the deeplinked location', (
      WidgetTester tester,
    ) async {
      final SessionController session = _session();
      bool authenticated = false;
      final GoRouter router = buildAppRouter(
        isAuthenticated: () => authenticated,
        initialLocation: '/settings?q=disk&sort=severity',
        loginBuilder: (BuildContext context, String returnTo) =>
            LoginScreen(session: session, returnTo: returnTo),
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();

      // Redirected to login, carrying the whole intended location.
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        find.text('returnTo=/settings?q=disk&sort=severity'),
        findsOneWidget,
      );

      session.addListener(() => authenticated = session.tokens != null);
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      // Landed on the target WITH its query, and the screen shows the restored
      // filters — the end of the deeplink -> login -> target journey.
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/settings?q=disk&sort=severity',
      );
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.text('text=disk'), findsOneWidget);
      expect(find.text('sort=severity'), findsOneWidget);
    });

    testWidgets('an unsafe returnTo lands on the safe default instead', (
      WidgetTester tester,
    ) async {
      // Defence in depth: even if a caller hands the screen a hostile value, the
      // screen re-validates at the point of use rather than trusting it.
      final SessionController session = _session();
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            home: LoginScreen(
              session: session,
              returnTo: 'https://evil.test/steal',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('returnTo=/home'), findsOneWidget);
    });
  });
}

/// A pumped `DieneApp` plus a handle on the router it built, so a test can drive
/// navigation through the SHIPPED shell rather than a router of its own.
final class _Shell {
  const _Shell(this.router);

  final GoRouter router;
}

/// Pumps the real [DieneApp]. When [authenticated] is true the session is signed
/// in first, so `session.tokens != null` — which is the value lib/app.dart reads.
Future<_Shell> _pumpShell(
  WidgetTester tester, {
  required bool authenticated,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences preferences = await SharedPreferences.getInstance();
  final AppConfig config = testConfig();
  final SessionController session = _session();
  if (authenticated) {
    await session.signIn();
  }
  await tester.pumpWidget(
    DieneApp(
      config: config,
      settings: AppSettingsController(config: config, preferences: preferences),
      session: session,
      preferences: preferences,
    ),
  );
  await tester.pumpAndSettle();
  // `GoRouter.of` needs a context BELOW the router, so it is read from the
  // rendered Scaffold rather than from the MaterialApp that owns it.
  return _Shell(GoRouter.of(tester.element(find.byType(Scaffold).first)));
}

/// A session controller over an in-memory gateway: enough to complete a real
/// sign-in without a network.
SessionController _session() {
  final AppConfig config = testConfig();
  return SessionController(
    provider: _MemoryAuthProvider(),
    onboarding: OnboardingCoordinator(
      homePicker: SingleRegionHomePicker(
        gateway: MemoryHomeClaimGateway(),
        landscape: 'lapras',
      ),
      gateway: DemoOnboardingGateway(),
      backendId: 'primary',
    ),
    accessLifetime: config.session.accessLifetime,
    refreshLifetime: config.session.refreshLifetime,
  );
}

final class _MemoryAuthProvider implements AuthProvider {
  int _rotation = 0;

  @override
  Future<SessionTokens> signIn({
    Map<String, String> extraParams = const <String, String>{},
  }) async => _tokens();

  @override
  Future<SessionTokens> refresh(SessionTokens current) async => _tokens();

  @override
  Future<SessionTokens> reMintOnOpen(SessionTokens current) async => _tokens();

  @override
  Future<void> signOut() async {}

  @override
  Future<engine.ResourceToken> resourceToken(engine.ResourceKey key) =>
      throw UnsupportedError('unused by routing tests');

  @override
  Future<String?> idToken() async => null;

  @override
  Future<String?> freshClaimToken() async => null;

  SessionTokens _tokens() {
    _rotation += 1;
    final DateTime now = DateTime.now().toUtc();
    return SessionTokens(
      accessToken: 'access-$_rotation',
      refreshToken: 'refresh-$_rotation',
      refreshFamily: 'login-screen-family',
      accessExpiresAt: now.add(const Duration(minutes: 10)),
      refreshExpiresAt: now.add(const Duration(days: 14)),
    );
  }
}

Widget _loginBuilder(BuildContext context, String returnTo) =>
    const _LoginStub();

/// The screens read copy through `context.t`, so the real translation provider
/// wraps them here rather than a stub — a screen that renders only under a fake
/// i18n surface has not been shown to render.
Widget _app(GoRouter router) =>
    TranslationProvider(child: MaterialApp.router(routerConfig: router));

final class _LoginStub extends StatelessWidget {
  const _LoginStub();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('login')));
}

Matcher _isSubsetOf(Set<String> superset) => predicate<Set<String>>(
  (Set<String> subject) => subject.every(superset.contains),
  'is a subset of $superset',
);
