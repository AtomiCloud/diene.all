'use client';

import {
  createCssVariableApplier,
  createThemeStore,
  type Appearance,
  type SystemAppearancePort,
  type ThemeStoragePort,
  type ThemeStore,
} from '@atomicloud/diene.frontend-utils/theme';
import type { ThemeConfig } from '@/config';
import { themeCssVariables } from '@/lib/tokens';

// Browser ports for the frontend-utils theme core. The core owns the
// mechanism (resolution/switching/persistence); these ports own the
// environment: localStorage, matchMedia, and the document element.

const storagePort = (): ThemeStoragePort => ({
  get: key => {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  set: (key, value) => {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // Storage unavailable (private mode) — theme still switches, just unpersisted.
    }
  },
});

const systemPort = (): SystemAppearancePort => {
  const query = window.matchMedia('(prefers-color-scheme: dark)');
  const appearance = (): Appearance => (query.matches ? 'dark' : 'light');
  return {
    get: appearance,
    subscribe: listener => {
      const handler = () => listener(appearance());
      query.addEventListener('change', handler);
      return () => query.removeEventListener('change', handler);
    },
  };
};

/** Wire the runtime CSS-variable theme store from the theme config block. */
export const createBrowserThemeStore = (theme: ThemeConfig): ThemeStore => {
  const cssVars = createCssVariableApplier(document.documentElement.style, themeCssVariables);
  return createThemeStore({
    config: { themes: theme.themes, fallback: theme.default },
    storage: storagePort(),
    system: systemPort(),
    applier: {
      apply: resolved => {
        cssVars.apply(resolved);
        document.documentElement.classList.toggle('dark', resolved.appearance === 'dark');
        document.documentElement.dataset['theme'] = resolved.name;
      },
    },
    storageKey: theme.storageKey,
  });
};
