/**
 * Deeplink route map — the single source of truth for BOTH directions of the
 * app↔web mapping. The format is agreed cross-track with flutter-base's
 * router: each entry pairs a web path pattern with an app route pattern over
 * identical `:param` placeholders, so either side can derive its half and a
 * conductor check can diff the two repos' maps for consistency.
 */

export interface DeeplinkRoute {
  /** Stable route id shared with the app router. */
  readonly id: string;
  /** Web path pattern, `:param` placeholders. */
  readonly web: string;
  /** App route pattern, same placeholders. */
  readonly app: string;
}

export const DEEPLINK_ROUTES: readonly DeeplinkRoute[] = [
  { id: 'home', web: '/', app: '/home' },
  { id: 'onboarding', web: '/onboarding', app: '/onboarding' },
  { id: 'finish', web: '/finish', app: '/onboarding/finish' },
  { id: 'profile', web: '/profile', app: '/profile' },
  { id: 'settings', web: '/settings', app: '/settings' },
];

const PARAM = /:([A-Za-z][A-Za-z0-9]*)/g;

const params = (pattern: string): readonly string[] => [...pattern.matchAll(PARAM)].map(match => match[1] ?? '');

/**
 * Validate the map BOTH ways: every web route maps to exactly one app route
 * and back, ids are unique, and both sides use the same parameter set. The
 * route-map gate runs this; an unmapped or asymmetric route is a red.
 */
export const validateRouteMap = (routes: readonly DeeplinkRoute[]): readonly string[] => {
  const errors: string[] = [];
  const ids = new Set<string>();
  const webs = new Set<string>();
  const apps = new Set<string>();
  for (const route of routes) {
    if (ids.has(route.id)) errors.push(`duplicate id: ${route.id}`);
    ids.add(route.id);
    if (webs.has(route.web)) errors.push(`duplicate web pattern: ${route.web}`);
    webs.add(route.web);
    if (apps.has(route.app)) errors.push(`duplicate app pattern: ${route.app}`);
    apps.add(route.app);
    const webParams = [...params(route.web)].sort();
    const appParams = [...params(route.app)].sort();
    if (webParams.join(',') !== appParams.join(',')) {
      errors.push(`param mismatch on ${route.id}: web(${webParams.join(',')}) app(${appParams.join(',')})`);
    }
  }
  return errors;
};

const matchPattern = (pattern: string, path: string): Readonly<Record<string, string>> | undefined => {
  const patternSegments = pattern.split('/').filter(Boolean);
  const pathSegments = path.split('/').filter(Boolean);
  if (patternSegments.length !== pathSegments.length) return undefined;
  const captured: Record<string, string> = {};
  for (const [index, segment] of patternSegments.entries()) {
    const value = pathSegments[index] ?? '';
    if (segment.startsWith(':')) captured[segment.slice(1)] = value;
    else if (segment !== value) return undefined;
  }
  return captured;
};

const substitute = (pattern: string, values: Readonly<Record<string, string>>): string =>
  pattern.replace(PARAM, (_, name: string) => values[name] ?? '');

/** web path → app route (undefined when unmapped). */
export const webToApp = (path: string, routes: readonly DeeplinkRoute[] = DEEPLINK_ROUTES): string | undefined => {
  for (const route of routes) {
    const captured = matchPattern(route.web, path);
    if (captured !== undefined) return substitute(route.app, captured);
  }
  return undefined;
};

/** app route → web path (undefined when unmapped). */
export const appToWeb = (path: string, routes: readonly DeeplinkRoute[] = DEEPLINK_ROUTES): string | undefined => {
  for (const route of routes) {
    const captured = matchPattern(route.app, path);
    if (captured !== undefined) return substitute(route.web, captured);
  }
  return undefined;
};
