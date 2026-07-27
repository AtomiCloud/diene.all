/// Deeplink route map — the single source of truth for BOTH directions of the
/// app↔web mapping.
///
/// ## The cross-track format contract
///
/// This format is agreed with the nextjs node (`src/lib/deeplink/route-map.ts`)
/// and is a CONTRACT, not an implementation detail. Both repos ship the same
/// table so a conductor sweep can diff the two maps as a literal comparison and
/// so the well-known documents (AASA / assetlinks) that nextjs serves cover
/// exactly the paths this app claims.
///
/// ### What this mirror is bound to
///
/// The literal-comparison property only holds against a FIXED counterpart, so
/// this mirror is pinned to a blob on a landed ref rather than to whatever a
/// working tree currently holds:
///
/// * counterpart path — `src/lib/deeplink/route-map.ts`
/// * blob   — `8fab918db8d9c1ea0d44a62651700890243e9390`
/// * commit — `889850b1922ce13f8b1d606974d11fe7e96fb69c`
///   ("feat: add app features for deeplink, picker, onboarding, and UX
///   patterns"), reachable from `authoritative/nextjs-frontend` and
///   `origin/nextjs-frontend`, both of which carry that identical blob.
///
/// If the web track revises its map, that blob hash stops matching and the
/// divergence is a DETECTABLE EVENT rather than silent drift. The frozen-table
/// assertion in `test/routing_route_map_test.dart` is the local half of the
/// same guard: it restates all five triples as literals, so editing this table
/// without re-pinning the blob above turns the gate red.
///
/// Re-verify the pin with:
///
/// ```sh
/// git ls-tree authoritative/nextjs-frontend -- src/lib/deeplink/route-map.ts
/// ```
///
/// A route is a triple:
///
/// * `id`  — stable route identity, shared verbatim across both repos. This is
///           what the app router names its `GoRoute`s after, and what a
///           navigation destination refers to.
/// * `web` — the web path pattern, using `:param` placeholders.
/// * `app` — the in-app route pattern, using the SAME placeholders.
///
/// Both sides use `:param` placeholders over `/`-delimited segments, and the
/// two halves of one entry must declare an identical parameter SET (order is
/// free — the mapping is by name, not position). That is what makes the map
/// invertible: [webToApp] and [appToWeb] are two views of one table rather than
/// two hand-maintained lists that can silently disagree.
///
/// Rules the format imposes (all enforced by [validateRouteMap]):
///
/// 1. `id`, `web` and `app` are each unique across the table.
/// 2. Both halves of an entry declare the same parameter names.
/// 3. Every pattern is rooted (`/…`) — a relative pattern is not a deeplink.
/// 4. No pattern segment mixes a placeholder with literal text.
///
/// Adding one unmapped route — an entry whose halves disagree, or a screen with
/// no entry at all — turns the route-map gate red. See
/// `test/routing_route_map_test.dart` (map validity, both directions) and
/// `test/routing_login_redirect_test.dart` (route-for-every-screen).
library;

import 'package:collection/collection.dart';

/// One entry in the deeplink route map: a web path pattern paired with the app
/// route pattern that serves the same destination.
final class DeeplinkRoute {
  const DeeplinkRoute({required this.id, required this.web, required this.app});

  /// Stable route id shared with the web track's map and with the app router.
  final String id;

  /// Web path pattern, `:param` placeholders.
  final String web;

  /// App route pattern, the same placeholders.
  final String app;

  @override
  String toString() => 'DeeplinkRoute($id: web=$web app=$app)';

  @override
  bool operator ==(Object other) =>
      other is DeeplinkRoute &&
      other.id == id &&
      other.web == web &&
      other.app == app;

  @override
  int get hashCode => Object.hash(id, web, app);
}

/// Canonical route ids. Every navigable destination names one of these, so a
/// typo becomes a compile error rather than a dead link.
abstract final class RouteIds {
  static const String home = 'home';
  static const String onboarding = 'onboarding';
  static const String finish = 'finish';
  static const String profile = 'profile';
  static const String settings = 'settings';
}

/// The shipped map. Mirrors the nextjs node's `DEEPLINK_ROUTES` entry for
/// entry — the ids, web patterns and app patterns are all identical, because a
/// conductor sweep compares the two tables directly.
const List<DeeplinkRoute> deeplinkRoutes = <DeeplinkRoute>[
  DeeplinkRoute(id: RouteIds.home, web: '/', app: '/home'),
  DeeplinkRoute(
    id: RouteIds.onboarding,
    web: '/onboarding',
    app: '/onboarding',
  ),
  DeeplinkRoute(id: RouteIds.finish, web: '/finish', app: '/onboarding/finish'),
  DeeplinkRoute(id: RouteIds.profile, web: '/profile', app: '/profile'),
  DeeplinkRoute(id: RouteIds.settings, web: '/settings', app: '/settings'),
];

final RegExp _param = RegExp(r':([A-Za-z][A-Za-z0-9]*)');

/// Parameter names declared by a pattern, in declaration order.
List<String> routeParameters(String pattern) => _param
    .allMatches(pattern)
    .map((RegExpMatch match) => match.group(1)!)
    .toList();

/// Validate the map BOTH ways. Returns the list of problems found; an empty
/// list means the table is a well-formed, invertible mapping.
///
/// This is the route-map gate's assertion. It is deliberately a list of
/// messages rather than a bool so a red tells you WHICH entry is wrong.
List<String> validateRouteMap(List<DeeplinkRoute> routes) {
  final List<String> errors = <String>[];
  final Set<String> ids = <String>{};
  final Set<String> webs = <String>{};
  final Set<String> apps = <String>{};
  for (final DeeplinkRoute route in routes) {
    if (!ids.add(route.id)) {
      errors.add('duplicate id: ${route.id}');
    }
    if (!webs.add(route.web)) {
      errors.add('duplicate web pattern: ${route.web}');
    }
    if (!apps.add(route.app)) {
      errors.add('duplicate app pattern: ${route.app}');
    }
    if (!route.web.startsWith('/')) {
      errors.add('web pattern is not rooted on ${route.id}: ${route.web}');
    }
    if (!route.app.startsWith('/')) {
      errors.add('app pattern is not rooted on ${route.id}: ${route.app}');
    }
    for (final MapEntry<String, String> side in <String, String>{
      'web': route.web,
      'app': route.app,
    }.entries) {
      for (final String segment in _segments(side.value)) {
        if (segment.contains(':') && !segment.startsWith(':')) {
          errors.add(
            '${side.key} pattern mixes a placeholder with literal text on '
            '${route.id}: $segment',
          );
        }
      }
    }
    final List<String> webParams = routeParameters(route.web)..sort();
    final List<String> appParams = routeParameters(route.app)..sort();
    if (!const ListEquality<String>().equals(webParams, appParams)) {
      errors.add(
        'param mismatch on ${route.id}: '
        'web(${webParams.join(',')}) app(${appParams.join(',')})',
      );
    }
  }
  return errors;
}

List<String> _segments(String pattern) =>
    pattern.split('/').where((String segment) => segment.isNotEmpty).toList();

Map<String, String>? _match(String pattern, String path) {
  final List<String> patternSegments = _segments(pattern);
  final List<String> pathSegments = _segments(path);
  if (patternSegments.length != pathSegments.length) {
    return null;
  }
  final Map<String, String> captured = <String, String>{};
  for (int index = 0; index < patternSegments.length; index += 1) {
    final String segment = patternSegments[index];
    final String value = pathSegments[index];
    if (segment.startsWith(':')) {
      captured[segment.substring(1)] = value;
    } else if (segment != value) {
      return null;
    }
  }
  return captured;
}

String _substitute(String pattern, Map<String, String> values) => pattern
    .replaceAllMapped(_param, (Match match) => values[match.group(1)] ?? '');

/// Web path → app route. `null` when the path is unmapped.
///
/// Only the PATH is translated; query and fragment are the caller's to carry
/// (see `lib/routing/deeplink.dart`, which translates whole URIs).
String? webToApp(String path, {List<DeeplinkRoute> routes = deeplinkRoutes}) {
  for (final DeeplinkRoute route in routes) {
    final Map<String, String>? captured = _match(route.web, path);
    if (captured != null) {
      return _substitute(route.app, captured);
    }
  }
  return null;
}

/// App route → web path. `null` when the route is unmapped.
String? appToWeb(String path, {List<DeeplinkRoute> routes = deeplinkRoutes}) {
  for (final DeeplinkRoute route in routes) {
    final Map<String, String>? captured = _match(route.app, path);
    if (captured != null) {
      return _substitute(route.web, captured);
    }
  }
  return null;
}

/// The entry whose app pattern matches [path], or `null` when unmapped.
DeeplinkRoute? routeForAppPath(
  String path, {
  List<DeeplinkRoute> routes = deeplinkRoutes,
}) => routes.firstWhereOrNull(
  (DeeplinkRoute route) => _match(route.app, path) != null,
);

/// The entry with id [id], or `null`.
DeeplinkRoute? routeById(
  String id, {
  List<DeeplinkRoute> routes = deeplinkRoutes,
}) => routes.firstWhereOrNull((DeeplinkRoute route) => route.id == id);
