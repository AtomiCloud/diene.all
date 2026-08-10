'use client';

import { ThemeProvider } from '@atomicloud/diene.frontend-utils/theme/react';
import type { ThemeStore } from '@atomicloud/diene.frontend-utils/theme';
import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import type { ClientSafeConfig } from '@/config';
import { ClientConfigProvider } from './ClientConfigProvider';
import { createBrowserThemeStore } from './theme';
import { buildModules, type AppModules } from './modules';
import { initFaro } from './faro';

const ModulesContext = createContext<AppModules | undefined>(undefined);

/**
 * The resolved module surface, or undefined during SSR/first paint (module
 * registration is async); consumers render their loading branch until it
 * lands one microtask later.
 */
export function useModules(): AppModules | undefined {
  return useContext(ModulesContext);
}

/** SSR-safe stand-in: applies nothing; the head init script owns first paint. */
const ssrThemeStore = (): ThemeStore => ({
  getPreference: () => 'system',
  getResolved: () => ({ preference: 'system', name: 'light', appearance: 'light' }),
  setTheme: () => undefined,
  subscribe: () => () => undefined,
  destroy: () => undefined,
});

/**
 * The client provider stack: SSR-injected config → module registry → runtime
 * theme. This is the single client boundary the root layout mounts; everything
 * below it can use the app's hooks.
 */
export function Providers({ config, children }: { readonly config: ClientSafeConfig; readonly children: ReactNode }) {
  // Both stores touch browser APIs, so they are created after mount; SSR
  // renders the static markup (no-flash theming is covered by the head init
  // script) and the client provider stack attaches on hydration.
  const [modules, setModules] = useState<AppModules | undefined>(undefined);
  const [themeStore, setThemeStore] = useState<ThemeStore | undefined>(undefined);

  useEffect(() => {
    let cancelled = false;
    void buildModules(config).then(built => {
      if (!cancelled) setModules(built);
    });
    return () => {
      cancelled = true;
    };
  }, [config]);

  useEffect(() => {
    const store = createBrowserThemeStore(config.theme);
    setThemeStore(store);
    return () => store.destroy();
  }, [config.theme]);

  useEffect(() => {
    initFaro(config);
  }, [config]);

  return (
    <ClientConfigProvider config={config}>
      <ModulesContext.Provider value={modules}>
        <ThemeProvider store={themeStore ?? ssrThemeStore()}>{children}</ThemeProvider>
      </ModulesContext.Provider>
    </ClientConfigProvider>
  );
}
