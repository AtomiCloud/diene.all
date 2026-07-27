/// The app router — `go_router`, built FROM the screen registry.
///
/// The router is derived, never hand-maintained alongside the registry. Every
/// `GoRoute` comes from a [ScreenDefinition] paired with its route-map entry, so
/// there is exactly one place a destination can be declared and the
/// route-for-every-screen check has something real to check.
///
/// ## What this file owns and what it does not
///
/// Owned here (route side):
///
/// * building the routes from the registry,
/// * the redirect that turns an unauthenticated hit on a protected route into a
///   login location carrying `returnTo` — path AND query preserved,
/// * consuming `returnTo` after authentication and continuing to it safely.
///
/// NOT owned here: whether a session exists. That is the auth gate
/// (`lib/auth/`), reached only through the [AuthStatus] callback below. The
/// router asks a question; it does not implement the answer.
library;

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../screens/app_screens.dart';
import '../screens/screen_registry.dart';
import 'deeplink.dart';
import 'route_map.dart';

/// Whether a session is currently established. Supplied by the session
/// controller; the router only reads it.
typedef AuthStatus = bool Function();

/// The in-app path of the login screen.
///
/// Login is deliberately NOT in the deeplink route map: it is not a shareable
/// destination and no web link should resolve to it. That is also why the
/// route-for-every-screen check runs over the registry rather than over the
/// router's whole route list.
const String loginPath = '/login';

/// The routes for the declared screens plus login, as a spliceable list.
///
/// Exposed separately from [buildAppRouter] so a host that already owns its
/// `GoRouter` (the app shell) can mount this surface without surrendering its
/// own routes. [buildAppRouter] is the same thing wrapped in a router.
List<RouteBase> appRouteBases({
  required Widget Function(BuildContext context, String returnTo) loginBuilder,
  List<ScreenDefinition> screens = const <ScreenDefinition>[],
}) {
  final List<ScreenDefinition> declared = screens.isEmpty
      ? appScreens
      : screens;
  return <RouteBase>[
    for (final ScreenDefinition screen in declared)
      GoRoute(
        name: screen.routeId,
        path: _pathOf(screen),
        builder: (BuildContext context, GoRouterState state) =>
            screen.builder(context, _contextOf(state)),
      ),
    GoRoute(
      path: loginPath,
      builder: (BuildContext context, GoRouterState state) => loginBuilder(
        context,
        // Fails closed: an off-origin or scheme-bearing returnTo becomes the
        // safe default rather than an open redirect.
        continueTo(state.uri.queryParameters[returnToParameter]),
      ),
    ),
  ];
}

/// Builds the app router.
///
/// [isAuthenticated] answers the session question. [loginBuilder] renders the
/// login screen, receiving the location to continue to once authentication
/// succeeds — that is where the auth gate hooks in.
///
/// [extraRoutes] lets the app shell keep routes it already owns (they are
/// mounted alongside, and are NOT subject to the protected-screen redirect,
/// which only knows about registry entries).
GoRouter buildAppRouter({
  required AuthStatus isAuthenticated,
  required Widget Function(BuildContext context, String returnTo) loginBuilder,
  List<ScreenDefinition> screens = const <ScreenDefinition>[],
  List<RouteBase> extraRoutes = const <RouteBase>[],
  String initialLocation = '/home',
  GlobalKey<NavigatorState>? navigatorKey,
}) {
  final List<ScreenDefinition> declared = screens.isEmpty
      ? appScreens
      : screens;
  return GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: initialLocation,
    routes: <RouteBase>[
      ...extraRoutes,
      ...appRouteBases(loginBuilder: loginBuilder, screens: declared),
    ],
    redirect: (BuildContext context, GoRouterState state) => redirectFor(
      location: state.uri.toString(),
      isAuthenticated: isAuthenticated(),
      screens: declared,
    ),
  );
}

/// The redirect decision, as a pure function of the location and session state.
///
/// Extracted from the `GoRouter` so it is testable without pumping a widget
/// tree: the login-redirect-return gate asserts on this directly, and the widget
/// test asserts the router actually uses it.
///
/// Returns `null` to proceed, or the location to redirect to.
String? redirectFor({
  required String location,
  required bool isAuthenticated,
  List<ScreenDefinition> screens = const <ScreenDefinition>[],
}) {
  final List<ScreenDefinition> declared = screens.isEmpty
      ? appScreens
      : screens;
  final Uri target = Uri.parse(location);
  final String path = target.path.isEmpty ? '/' : target.path;

  if (path == loginPath) {
    // Already authenticated? Do not sit on the login screen — continue to the
    // pending destination, which is the RETURN half of the round trip.
    if (isAuthenticated) {
      return continueTo(target.queryParameters[returnToParameter]);
    }
    return null;
  }

  final ScreenDefinition? screen = _screenFor(path, declared);
  if (screen == null || !screen.protected || isAuthenticated) {
    return null;
  }

  // The whole intended location — path AND query — is what gets preserved.
  // Carrying only the path is the sabotage this gate catches: it looks like a
  // working redirect and silently drops the filters the link was about.
  return buildLoginLocation(loginPath, location);
}

/// Every route id the registry declares.
Set<String> declaredScreenIds([List<ScreenDefinition>? screens]) =>
    (screens ?? appScreens)
        .map((ScreenDefinition screen) => screen.routeId)
        .toSet();

/// Registry entries whose route id has no entry in the route map.
///
/// This is the route-for-every-screen gate's assertion. A non-empty result names
/// exactly which screens are unreachable by link.
List<ScreenDefinition> screensWithoutRoutes([
  List<ScreenDefinition>? screens,
  List<DeeplinkRoute> routes = deeplinkRoutes,
]) => (screens ?? appScreens)
    .where(
      (ScreenDefinition screen) =>
          routeById(screen.routeId, routes: routes) == null,
    )
    .toList();

String _pathOf(ScreenDefinition screen) {
  final DeeplinkRoute? route = routeById(screen.routeId);
  if (route == null) {
    // A screen with no route cannot be given a path. Failing here rather than
    // inventing one keeps the defect visible instead of shipping a destination
    // that no link can reach.
    throw StateError(
      'screen "${screen.routeId}" has no route-map entry; '
      'add one to deeplinkRoutes or remove the screen',
    );
  }
  return route.app;
}

ScreenDefinition? _screenFor(String path, List<ScreenDefinition> screens) {
  for (final ScreenDefinition screen in screens) {
    final DeeplinkRoute? route = routeById(screen.routeId);
    if (route == null) {
      continue;
    }
    if (routeForAppPath(path) == route) {
      return screen;
    }
  }
  return null;
}

ScreenRouteContext _contextOf(GoRouterState state) => ScreenRouteContext(
  location: state.uri.toString(),
  pathParameters: state.pathParameters,
  queryParameters: state.uri.queryParameters,
);
