/// The screen registry — the enumerable list of navigable destinations.
///
/// ## Why a registry exists
///
/// "Every screen has a route" is only checkable if screens can be ENUMERATED.
/// A `GoRouter` built from an inline literal cannot be enumerated against
/// anything: a widget someone pushed with `Navigator.push` is a screen with no
/// route, and nothing notices. So every navigable destination is declared here
/// once, keyed by the route id from the deeplink route map, and the router is
/// BUILT from this list rather than kept in step with it by hand.
///
/// That makes the route-for-every-screen gate a real check with a real red: a
/// [ScreenDefinition] whose [routeId] has no entry in `deeplinkRoutes` fails
/// `test/routing_login_redirect_test.dart`. It also makes the subset direction
/// meaningful — navigation destinations are a SUBSET of the route map, so the
/// map may legitimately carry a web-only path the app does not render, but the
/// app may never render a destination the map does not carry.
///
/// [ScreenDefinition.protected] is the route-side half of the login-redirect
/// contract: the redirect that acts on it lives in `lib/routing/app_router.dart`
/// and the session check behind it is W3's auth gate.
library;

import 'package:flutter/widgets.dart';

import '../routing/route_map.dart';

/// One navigable destination.
final class ScreenDefinition {
  const ScreenDefinition({
    required this.routeId,
    required this.title,
    required this.builder,
    this.protected = false,
  });

  /// The route id this screen is reached by. MUST have an entry in
  /// `deeplinkRoutes` — that is the route-for-every-screen invariant.
  final String routeId;

  /// Debug/semantic title. Not user-facing copy (that comes from the i18n
  /// bundle inside the screen); this is what an enumeration prints.
  final String title;

  /// Builds the screen. Route parsing happens here, at the edge, so the widget
  /// tree below receives values rather than a `GoRouterState` (screen standard:
  /// keep route parsing outside the render tree).
  final Widget Function(BuildContext context, ScreenRouteContext route) builder;

  /// Whether reaching this screen requires an authenticated session. A
  /// protected screen deeplinked to while unauthenticated redirects to login
  /// carrying `returnTo`.
  final bool protected;

  /// The route-map entry for this screen, or `null` when the screen has no
  /// route — which is exactly the failure the gate reports.
  DeeplinkRoute? get route => routeById(routeId);

  @override
  String toString() =>
      'ScreenDefinition($routeId, protected=$protected, title=$title)';
}

/// What a screen builder is given: the parsed route, with no `go_router` type
/// leaking into the screen's own signature.
final class ScreenRouteContext {
  const ScreenRouteContext({
    required this.location,
    required this.pathParameters,
    required this.queryParameters,
  });

  /// The full current location (path + query), i.e. the shareable string.
  final String location;

  /// Path parameters captured by the route pattern.
  final Map<String, String> pathParameters;

  /// Query parameters — the url-as-state channel.
  final Map<String, String> queryParameters;

  /// The path half of [location].
  String get path => Uri.parse(location).path;
}

/// Ids of screens that must exist. Named so a registry that silently loses a
/// screen is a red rather than a smaller app.
abstract final class ScreenIds {
  static const String home = RouteIds.home;
  static const String onboarding = RouteIds.onboarding;
  static const String finish = RouteIds.finish;
  static const String profile = RouteIds.profile;
  static const String settings = RouteIds.settings;
}

/// Screen ids that require an authenticated session.
const Set<String> protectedScreenIds = <String>{
  ScreenIds.profile,
  ScreenIds.settings,
  ScreenIds.finish,
};
