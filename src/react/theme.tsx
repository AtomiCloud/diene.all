import { createContext, type ReactNode, useContext, useSyncExternalStore } from 'react';
import type { ResolvedTheme, ThemePreference, ThemeStore } from '../lib/theme/index.js';

/**
 * React binding for the theme store.
 *
 * Thin adapter only: a provider carries a {@link ThemeStore} (built with the
 * React-free core and browser adapters) and {@link useTheme} exposes the
 * resolved theme, a dark-mode flag, and the switcher. All resolution,
 * persistence, and CSS-variable application live in the core.
 */

const ThemeStoreContext = createContext<ThemeStore | null>(null);

export interface ThemeProviderProps {
  readonly store: ThemeStore;
  readonly children: ReactNode;
}

/** Provide a theme store to the subtree. */
export const ThemeProvider = ({ store, children }: ThemeProviderProps): ReactNode => (
  <ThemeStoreContext.Provider value={store}>{children}</ThemeStoreContext.Provider>
);

export interface ThemeApi {
  readonly resolved: ResolvedTheme;
  /** The effective (validated) preference — `'system'`, a built-in, or a named theme. */
  readonly preference: ThemePreference;
  /** Convenience dark-mode flag riding the same mechanism. */
  readonly isDark: boolean;
  readonly setTheme: (preference: ThemePreference) => void;
}

/** Access the current theme and switcher. Throws outside a {@link ThemeProvider}. */
export const useTheme = (): ThemeApi => {
  const store = useContext(ThemeStoreContext);
  if (store === null) throw new Error('useTheme must be used within a ThemeProvider');
  const resolved = useSyncExternalStore(store.subscribe, store.getResolved, store.getResolved);
  return {
    resolved,
    preference: resolved.preference,
    isDark: resolved.appearance === 'dark',
    setTheme: store.setTheme,
  };
};
