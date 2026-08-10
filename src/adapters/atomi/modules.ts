import { createModuleRegistry, defineModule, type ModuleRegistry } from '@atomicloud/diene.frontend-utils/module';
import { createContentStore, createProblemViewRegistry } from '@atomicloud/diene.frontend-utils/content';
import type { ContentStore, ProblemViewRegistry } from '@atomicloud/diene.frontend-utils/content/react';
import type { ReactNode } from 'react';
import type { ClientSafeConfig } from '@/config';
import { defaultProblemView } from '@/components/problem/DefaultProblemView';

/**
 * Template-side DI wiring over the lib's module contract (redesign LICENSED —
 * argon's provider soup is replaced with one typed registry). The lib owns the
 * contract + resolver; this file owns which modules exist and how they wire.
 */

const MODULE_IDS = {
  problemViews: 'problem-views',
  contentStore: 'content-store',
} as const;

/** Framework-agnostic Problem-view registry, shared by every error boundary. */
const problemViewsModule = defineModule<ProblemViewRegistry<ReactNode>, ClientSafeConfig>({
  id: MODULE_IDS.problemViews,
  create: () => createProblemViewRegistry<ReactNode>(defaultProblemView),
});

/** Factory for L/E/E content stores; pages create one store per content unit. */
const contentStoreModule = defineModule<<T>() => ContentStore<T>, ClientSafeConfig>({
  id: MODULE_IDS.contentStore,
  create: () => createContentStore,
});

/** The resolved module surface consumed through React context. */
export interface AppModules {
  readonly registry: ModuleRegistry;
  readonly problemViews: ProblemViewRegistry<ReactNode>;
  readonly createContentStore: <T>() => ContentStore<T>;
}

const required = async <T>(registry: ModuleRegistry, id: string): Promise<T> =>
  registry.resolve<T>(id).match({
    ok: value => value,
    err: error => {
      throw new Error(`module resolution failed: ${error.kind} (${error.id})`);
    },
  });

/**
 * Build the app's module registry from the SSR-injected client-safe config and
 * resolve the app-wide modules through it (the DI resolution path the module
 * gate exercises). Registration results are async-native Results; ids are
 * unique by construction, so a failure is a programming error — surfaced loudly.
 */
export const buildModules = async (config: ClientSafeConfig): Promise<AppModules> => {
  const registry = createModuleRegistry();
  for (const registration of [
    registry.register(problemViewsModule, config),
    registry.register(contentStoreModule, config),
  ]) {
    await registration.match({
      ok: () => undefined,
      err: error => {
        throw new Error(`module registration failed: ${error.kind} (${error.id})`);
      },
    });
  }
  return {
    registry,
    problemViews: await required<ProblemViewRegistry<ReactNode>>(registry, MODULE_IDS.problemViews),
    createContentStore: await required<<T>() => ContentStore<T>>(registry, MODULE_IDS.contentStore),
  };
};
