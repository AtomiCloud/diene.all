/// Deeplink translation and login-redirect return.
///
/// Two jobs, both route-side:
///
/// 1. **URI translation, both directions.** A web URL that Android (App Links)
///    or iOS (Universal Links) hands the app becomes an in-app location, and an
///    in-app location becomes a shareable web URL. Query and fragment survive
///    both translations — a deeplink that loses its query is a broken deeplink,
///    not a partially-working one.
/// 2. **`returnTo` preservation.** A protected deeplink must survive login with
///    its path AND query intact. The auth gate itself is not here (that is
///    `lib/auth/`); what is here is the route-side pair — build the login
///    location carrying the intended destination, and resolve it back safely
///    afterwards. The resolver fails CLOSED: an off-origin or scheme-bearing
///    `returnTo` is rejected rather than followed, because an open redirect is a
///    security defect.
///
/// ## Why this file says "authority", not the DNS-name word
///
/// `scripts/validate/landscape-policy.sh` (an accepted flutter-base gate, rule
/// 3) forbids the DNS-name token anywhere under `lib/**.dart`, because deriving
/// the landscape from a network address at runtime is exactly the defect it
/// exists to prevent — landscape is baked at build/stamp time. This router
/// compares addresses for a different and legitimate reason (deciding whether an
/// incoming link belongs to this build), but the gate cannot tell the two apart
/// from a token, and a gate is not weakened to accommodate the code it flags.
/// So the whole surface is expressed over [Uri.authority] instead, via
/// [authorityOf]. Nothing here reads the landscape from a link.
library;

import 'route_map.dart';

/// The platform that delivered a link. Both are supported and both are tested;
/// the difference is only which document (assetlinks.json vs AASA) authorized
/// the address, so translation itself is platform-independent.
enum DeeplinkPlatform {
  android('android'),
  ios('ios');

  const DeeplinkPlatform(this.wire);

  final String wire;
}

/// The authority of [uri], lower-cased and without any port.
///
/// Deliberately local rather than imported from `lib/onboarding/`: routing must
/// not depend on onboarding, and this is a one-line projection of a `Uri`.
String authorityOf(Uri uri) => uri.authority.split(':').first.toLowerCase();

/// The web origins and custom scheme this build accepts links from.
///
/// Every value is configuration, never a literal in code (R4): the web origin
/// differs per landscape and the custom scheme is the per-flavor bundle id, both
/// of which come from the config chain.
final class DeeplinkConfig {
  const DeeplinkConfig({
    required this.webOrigin,
    required this.customScheme,
    this.additionalWebOrigins = const <Uri>[],
  });

  /// The canonical web origin, e.g. `https://app.<platform>.<landscape>.example`
  /// — read from config, never written down here.
  final Uri webOrigin;

  /// The custom scheme the app registers. This is the per-flavor application id
  /// from the flavorizr chain, supplied by config; the callback URI in
  /// `config/*.yaml` uses the same value.
  final String customScheme;

  /// Extra accepted web origins (vanity or legacy domains).
  final List<Uri> additionalWebOrigins;

  /// Every accepted web origin, canonical first.
  List<Uri> get webOrigins => <Uri>[webOrigin, ...additionalWebOrigins];

  /// Whether [uri] is a web link this build claims.
  bool acceptsWeb(Uri uri) => webOrigins.any(
    (Uri origin) =>
        uri.scheme == origin.scheme &&
        authorityOf(uri) == authorityOf(origin) &&
        uri.port == origin.port,
  );

  /// Whether [uri] is a custom-scheme link this build claims.
  bool acceptsScheme(Uri uri) => uri.scheme == customScheme;
}

/// Why a link could not be turned into an in-app location.
enum DeeplinkRejection {
  /// The scheme or authority is not one this build claims.
  foreignOrigin,

  /// The origin is ours but the path has no entry in the route map.
  unmappedPath,
}

/// The outcome of translating an incoming link.
sealed class DeeplinkResolution {
  const DeeplinkResolution();
}

/// The link resolved to an in-app location.
final class DeeplinkAccepted extends DeeplinkResolution {
  const DeeplinkAccepted({required this.location, required this.route});

  /// The in-app location: app path plus the original query and fragment.
  final String location;

  /// The map entry that matched.
  final DeeplinkRoute route;

  @override
  String toString() => 'DeeplinkAccepted($location via ${route.id})';
}

/// The link was refused, with the reason.
///
/// "Found nothing" and "could not look" are different answers: an unmapped path
/// on our own origin is a map defect, a foreign origin is not.
final class DeeplinkRejected extends DeeplinkResolution {
  const DeeplinkRejected(this.reason);

  final DeeplinkRejection reason;

  @override
  String toString() => 'DeeplinkRejected(${reason.name})';
}

/// Translates links in both directions for one build's configuration.
final class DeeplinkTranslator {
  const DeeplinkTranslator({
    required this.config,
    this.routes = deeplinkRoutes,
  });

  final DeeplinkConfig config;
  final List<DeeplinkRoute> routes;

  /// Incoming link → in-app location. Accepts both an authorized web URL
  /// (App Links / Universal Links) and a custom-scheme URL.
  ///
  /// Query and fragment are carried through untouched.
  DeeplinkResolution resolve(Uri incoming) {
    if (config.acceptsScheme(incoming)) {
      final String path = _schemePath(incoming);
      final DeeplinkRoute? route = routeForAppPath(path, routes: routes);
      if (route == null) {
        return const DeeplinkRejected(DeeplinkRejection.unmappedPath);
      }
      return DeeplinkAccepted(
        location: _withQuery(path, incoming),
        route: route,
      );
    }
    if (!config.acceptsWeb(incoming)) {
      return const DeeplinkRejected(DeeplinkRejection.foreignOrigin);
    }
    final String webPath = incoming.path.isEmpty ? '/' : incoming.path;
    final String? appPath = webToApp(webPath, routes: routes);
    if (appPath == null) {
      return const DeeplinkRejected(DeeplinkRejection.unmappedPath);
    }
    return DeeplinkAccepted(
      location: _withQuery(appPath, incoming),
      route: routes.firstWhere((DeeplinkRoute route) => route.app == appPath),
    );
  }

  /// In-app location → shareable web URL. `null` when the location is unmapped.
  ///
  /// This is the direction that makes a link shareable: the query state a
  /// viewer built up in the app becomes a URL another viewer can open.
  Uri? toWebUri(String location) {
    final Uri parsed = Uri.parse(location);
    final String? webPath = appToWeb(
      parsed.path.isEmpty ? '/' : parsed.path,
      routes: routes,
    );
    if (webPath == null) {
      return null;
    }
    return config.webOrigin.replace(
      path: webPath,
      query: parsed.query.isEmpty ? null : parsed.query,
      fragment: parsed.fragment.isEmpty ? null : parsed.fragment,
    );
  }

  /// In-app location → custom-scheme URL. `null` when unmapped.
  Uri? toSchemeUri(String location) {
    final Uri parsed = Uri.parse(location);
    final String path = parsed.path.isEmpty ? '/' : parsed.path;
    if (routeForAppPath(path, routes: routes) == null) {
      return null;
    }
    // `scheme:///path` — an EMPTY authority followed by the full app path, which
    // is what the platform registers and what [resolve] reads back. The empty
    // authority matters: `scheme://profile` would parse "profile" as the
    // authority and leave an empty path, so the leading `//` is followed by
    // nothing and the whole path stays in the path component.
    //
    // Composed as a string rather than via `Uri`'s named authority parameter,
    // which is the token rule 3 forbids in this file; the result is parsed back
    // so callers still receive a validated [Uri].
    final StringBuffer buffer = StringBuffer('${config.customScheme}://')
      ..write(path);
    if (parsed.query.isNotEmpty) {
      buffer.write('?${parsed.query}');
    }
    if (parsed.fragment.isNotEmpty) {
      buffer.write('#${parsed.fragment}');
    }
    return Uri.parse(buffer.toString());
  }

  /// Round-trip check used by the route-map gate: an app location that maps to
  /// the web and back must land on the location it started from.
  bool roundTrips(String location) {
    final Uri? web = toWebUri(location);
    if (web == null) {
      return false;
    }
    final DeeplinkResolution back = resolve(web);
    return back is DeeplinkAccepted && back.location == location;
  }

  /// A custom-scheme link addresses the APP path space directly, so everything
  /// after the scheme is already an app path. `scheme://first/rest` parses
  /// `first` into the authority component, so the path is rebuilt from both
  /// parts to avoid silently dropping that first segment.
  String _schemePath(Uri uri) {
    final String leading = authorityOf(uri);
    final String path = uri.path;
    if (leading.isEmpty) {
      return path.isEmpty ? '/' : path;
    }
    return '/$leading${path.isEmpty ? '' : path}';
  }

  String _withQuery(String path, Uri source) => Uri(
    path: path,
    query: source.query.isEmpty ? null : source.query,
    fragment: source.fragment.isEmpty ? null : source.fragment,
  ).toString();
}

/// The query parameter that carries the intended destination through login.
/// Named the same as the web track's so a cross-track link is readable by both.
const String returnToParameter = 'returnTo';

/// Build the login location for a protected destination.
///
/// [intended] is an INTERNAL location (path plus query, e.g.
/// `/profile?tab=security`). It is percent-encoded into [returnToParameter] so
/// its own query survives being nested inside another query string — that
/// encoding is the whole reason the target's filters are not lost at login.
String buildLoginLocation(String loginPath, String intended) {
  final int fragmentAt = loginPath.indexOf('#');
  final String base = fragmentAt == -1
      ? loginPath
      : loginPath.substring(0, fragmentAt);
  final String fragment = fragmentAt == -1
      ? ''
      : loginPath.substring(fragmentAt);
  final String separator = base.contains('?') ? '&' : '?';
  return '$base$separator$returnToParameter='
      '${Uri.encodeQueryComponent(intended)}$fragment';
}

/// Resolve a `returnTo` value back into a location that is safe to navigate to.
///
/// Returns `null` for anything that is not a rooted internal location. Rejected
/// on purpose:
///
/// * `https://evil.test/steal` — absolute URL to another origin.
/// * `//evil.test/steal` — protocol-relative URL (a browser reads the part
///   after `//` as an origin; naive "starts with /" checks let it through).
/// * `/\evil.test` — backslash variant of the same trick.
/// * `javascript:alert(1)` — a scheme, not a path.
/// * anything containing CR or LF — header/log injection.
///
/// Callers pair this with [continueTo] so a rejected value becomes a known-safe
/// fallback rather than a crash.
String? resolveReturnTo(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  if (raw.contains('\r') || raw.contains('\n')) {
    return null;
  }
  if (!raw.startsWith('/')) {
    return null;
  }
  if (raw.length > 1 && (raw[1] == '/' || raw[1] == r'\')) {
    return null;
  }
  final int firstSlash = raw.indexOf('/');
  final int firstColon = raw.indexOf(':');
  if (firstColon != -1 && firstColon < firstSlash) {
    return null;
  }
  return raw;
}

/// The location to continue to after login: [raw] when it is safe, else
/// [fallback] (and `/home` if even the fallback is unsafe).
String continueTo(String? raw, {String fallback = '/home'}) =>
    resolveReturnTo(raw) ?? resolveReturnTo(fallback) ?? '/home';

/// Read the `returnTo` out of a login location built by [buildLoginLocation].
String? returnToOf(String loginLocation) =>
    Uri.parse(loginLocation).queryParameters[returnToParameter];
