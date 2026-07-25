'use client';

import { ThemeProvider } from '@atomicloud/diene.frontend-utils/theme/react';
import type { ThemeStore } from '@atomicloud/diene.frontend-utils/theme';
import { createContext, useContext, useEffect, useMemo, useState, type ReactNode } from 'react';
import type { ClientSafeConfig } from '@/config';
import { ClientConfigProvider } from './ClientConfigProvider';
import { createBrowserThemeStore } from './theme';
import { buildModules, type AppModules } from './modules';
import { initFaro } from './faro';

const ModulesContext = createContext<AppModules | undefined>(undefined);

export function useModules(): AppModules {
  const modules = useContext(ModulesContext);
  if (modules === undefined) {
    throw new Error('useModules must be used inside Providers');
  }
  return modules;
}

/**
 * The client provider stack: SSR-injected config → module registry → runtime
 * theme. This is the single client boundary the root layout mounts; everything
 * below it can use the app's hooks.
 */
export function Providers({ config, children }: { readonly config: ClientSafeConfig; readonly children: ReactNode }) {
  const themeStore = useMemo<ThemeStore>(() => createBrowserThemeStore(config.theme), [config.theme]);
  const [modules, setModules] = useState<AppModules | undefined>(undefined);

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
    initFaro(config);
  }, [config]);

  useEffect(() => () => themeStore.destroy(), [themeStore]);

  if (modules === undefined) {
    // One microtask of module registration; nothing user-visible flashes.
    return null;
  }

  return (
    <ClientConfigProvider config={config}>
      <ModulesContext.Provider value={modules}>
        <ThemeProvider store={themeStore}>{children}</ThemeProvider>
      </ModulesContext.Provider>
    </ClientConfigProvider>
  );
}
