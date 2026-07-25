import { createGenericProblemRegistry, type ProblemRegistry } from '@atomicloud/diene.problems';
import { registerApiProblems, type ApiProblems } from '@atomicloud/diene.api-engine';
import type { Problem } from '@atomicloud/diene.problems';
import type { Result } from '@atomicloud/diene.result';
import type { AppConfig, SeoConfig } from '@/config';

export interface AppProblems {
  readonly registry: ProblemRegistry;
  readonly api: ApiProblems;
}

/**
 * The app's Problem registry: generic problems plus the api-engine set,
 * addressed by this service's error portal (RFC 9457 `type` URIs resolve to
 * the published error-info documents).
 */
export const buildProblemRegistry = (
  app: AppConfig,
  seo: SeoConfig,
  landscape: string,
): Result<AppProblems, Problem> => {
  const base = new URL(seo.baseUrl);
  const registry = createGenericProblemRegistry({
    scheme: base.protocol === 'http:' ? 'http' : 'https',
    host: base.host,
    landscape,
    platform: app.servicetree.platform,
    service: app.servicetree.service,
    module: app.servicetree.module,
  });
  return registerApiProblems(registry).map(api => ({ registry, api }));
};
