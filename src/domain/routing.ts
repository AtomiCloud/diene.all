import type { LandscapeRuntimeConfig, ResolvedRoute } from './models.ts';

const tenantPathPrefix = '/t/';

const exactRegisteredDomain = (host: string | undefined, registeredDomain: string): boolean =>
  host !== undefined && host.toLowerCase() === registeredDomain.toLowerCase();

/**
 * Resolves only from compiled registration state. Host is consulted solely for
 * exact custom-domain lookup and is never parsed into tenant identity.
 */
export class NameBlindRouteResolver {
  resolve(config: LandscapeRuntimeConfig, path: string, host?: string): ResolvedRoute | null {
    if (path.startsWith(tenantPathPrefix)) {
      for (const tenant of config.tenants) {
        for (const route of tenant.routes) {
          if (route.canonicalPath === path) {
            return {
              tenant,
              route,
              orphaned: route.orphanedUntilMs !== undefined,
            };
          }
        }
      }
      return null;
    }

    if (host === undefined) {
      return null;
    }

    for (const tenant of config.tenants) {
      if (!tenant.registeredDomains.some(domain => exactRegisteredDomain(host, domain))) {
        continue;
      }
      const route = tenant.routes.find(candidate => candidate.path === path);
      if (route !== undefined) {
        return { tenant, route, orphaned: route.orphanedUntilMs !== undefined };
      }
    }

    return null;
  }
}
