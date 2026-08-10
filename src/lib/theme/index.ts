/**
 * Theme module — runtime, CSS-variable-driven theme resolution with
 * persistence and no-flash first paint.
 *
 * The core owns the MECHANISM only (resolution, switching, persistence): it has
 * zero token/colour opinions. All environment access (storage, system
 * appearance, applying to the document) is behind injected ports, so the core
 * is React-free and SSR-safe.
 */

export type Appearance = 'light' | 'dark';

/** A theme preference is `'system'`, a built-in appearance, or a named theme. */
export type ThemePreference = string;

export const SYSTEM_PREFERENCE = 'system';
export const DEFAULT_THEME_STORAGE_KEY = 'theme';

/** The concrete theme applied to the document after resolution. */
export interface ResolvedTheme {
  /** The preference that produced this resolution (may be `'system'`). */
  readonly preference: ThemePreference;
  /** The concrete theme name applied — never `'system'`. */
  readonly name: string;
  /** The effective light/dark appearance. */
  readonly appearance: Appearance;
}

export interface ThemeConfig {
  /** Named theme → appearance. `light`/`dark` are always available regardless. */
  readonly themes?: Readonly<Record<string, Appearance>>;
  /** Preference used when the requested/stored one is unknown. Defaults to `'system'`. */
  readonly fallback?: ThemePreference;
}

/** Read/write port for persisted preference (e.g. localStorage). */
export interface ThemeStoragePort {
  readonly get: (key: string) => string | null;
  readonly set: (key: string, value: string) => void;
}

/** Port exposing the OS colour-scheme and change notifications. */
export interface SystemAppearancePort {
  readonly get: () => Appearance;
  readonly subscribe: (listener: (appearance: Appearance) => void) => () => void;
}

/** Port that applies a resolved theme to the render target (CSS vars/classes). */
export interface ThemeApplierPort {
  readonly apply: (resolved: ResolvedTheme) => void;
}

/** A CSS custom-property name. Values and names are entirely consumer-authored. */
export type CssVariableName = `--${string}`;
export type CssVariableValues = Readonly<Partial<Record<CssVariableName, string>>>;
export type CssVariableThemeMap = Readonly<Record<string, CssVariableValues>>;

/** Structural style target; a browser `CSSStyleDeclaration` satisfies this port. */
export interface CssVariableTargetPort {
  readonly setProperty: (name: CssVariableName, value: string) => void;
  readonly removeProperty: (name: CssVariableName) => void;
}

/**
 * Build a theme applier that switches consumer-authored CSS variables at
 * runtime. Variables absent from the next theme are removed, so stale token
 * values cannot leak across switches. The map carries no library-owned visual
 * opinions.
 */
export const createCssVariableApplier = (
  target: CssVariableTargetPort,
  themes: CssVariableThemeMap,
): ThemeApplierPort => {
  let appliedNames: readonly CssVariableName[] = [];

  return {
    apply(resolved) {
      const nextVariables = themes[resolved.name] ?? {};
      for (const name of appliedNames) {
        if (!(name in nextVariables)) target.removeProperty(name);
      }
      for (const [name, value] of Object.entries(nextVariables) as [CssVariableName, string][]) {
        target.setProperty(name, value);
      }
      appliedNames = Object.keys(nextVariables) as CssVariableName[];
    },
  };
};

const appearanceMap = (config: ThemeConfig): Record<string, Appearance> => ({
  ...config.themes,
  light: 'light',
  dark: 'dark',
});

/**
 * Resolve a preference into a concrete theme. Unknown preferences fall back to
 * `config.fallback` (or `'system'`); an unknown fallback degrades to system.
 * Pure and deterministic.
 */
export const resolveTheme = (
  preference: ThemePreference,
  system: Appearance,
  config: ThemeConfig = {},
): ResolvedTheme => {
  const map = appearanceMap(config);
  if (preference === SYSTEM_PREFERENCE) return { preference: SYSTEM_PREFERENCE, name: system, appearance: system };
  const appearance = map[preference];
  if (appearance !== undefined) return { preference, name: preference, appearance };

  const fallback = config.fallback ?? SYSTEM_PREFERENCE;
  if (fallback === SYSTEM_PREFERENCE) return { preference: SYSTEM_PREFERENCE, name: system, appearance: system };
  const fallbackAppearance = map[fallback];
  return fallbackAppearance !== undefined
    ? { preference: fallback, name: fallback, appearance: fallbackAppearance }
    : { preference: SYSTEM_PREFERENCE, name: system, appearance: system };
};

export type ResolvedThemeListener = (resolved: ResolvedTheme) => void;

export interface ThemeStore {
  readonly getPreference: () => ThemePreference;
  readonly getResolved: () => ResolvedTheme;
  readonly setTheme: (preference: ThemePreference) => void;
  readonly subscribe: (listener: ResolvedThemeListener) => () => void;
  /** Unsubscribe from the system port and drop all listeners. */
  readonly destroy: () => void;
}

export interface ThemeStoreOptions {
  readonly config?: ThemeConfig;
  readonly storage: ThemeStoragePort;
  readonly system: SystemAppearancePort;
  readonly applier: ThemeApplierPort;
  readonly storageKey?: string;
}

/**
 * Create a subscribable theme store. On construction it reads the persisted
 * preference and current system appearance, resolves, and applies once. Theme
 * switches persist and re-apply through the runtime CSS-variable mechanism;
 * system-appearance changes re-resolve automatically. {@link ThemeStore.destroy}
 * releases the system subscription.
 */
export const createThemeStore = (options: ThemeStoreOptions): ThemeStore => {
  const config = options.config ?? {};
  const key = options.storageKey ?? DEFAULT_THEME_STORAGE_KEY;
  const listeners = new Set<ResolvedThemeListener>();

  let preference: ThemePreference = options.storage.get(key) ?? SYSTEM_PREFERENCE;
  let systemAppearance = options.system.get();
  let resolved = resolveTheme(preference, systemAppearance, config);
  options.applier.apply(resolved);

  const recompute = (): void => {
    resolved = resolveTheme(preference, systemAppearance, config);
    options.applier.apply(resolved);
    for (const listener of listeners) listener(resolved);
  };

  const unsubscribeSystem = options.system.subscribe(appearance => {
    systemAppearance = appearance;
    recompute();
  });

  return {
    getPreference: () => preference,
    getResolved: () => resolved,
    setTheme(next) {
      preference = next;
      options.storage.set(key, next);
      recompute();
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    destroy() {
      unsubscribeSystem();
      listeners.clear();
    },
  };
};

export interface ThemeInitScriptOptions {
  readonly storageKey?: string;
  /** Named theme → appearance, baked so named themes resolve at first paint. */
  readonly themes?: Readonly<Record<string, Appearance>>;
}

/**
 * Produce a synchronous, side-effecting `<script>` body that resolves and
 * applies the persisted theme BEFORE first paint, eliminating the flash of the
 * wrong theme. It sets the appearance (`light`/`dark`) class and a
 * `data-theme` attribute (the preference, or the resolved appearance when
 * `'system'`). Pure string builder — safe to render server-side.
 */
export const themeInitScript = (options: ThemeInitScriptOptions = {}): string => {
  const key = options.storageKey ?? DEFAULT_THEME_STORAGE_KEY;
  const themes = JSON.stringify(options.themes ?? {});
  return [
    '(function(){try{',
    `var k=${JSON.stringify(key)};`,
    `var themes=${themes};`,
    "var p=localStorage.getItem(k)||'system';",
    "var m=window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light';",
    "var a=p==='system'?m:(themes[p]||(p==='dark'?'dark':(p==='light'?'light':m)));",
    'var e=document.documentElement;',
    "e.classList.remove('light','dark');e.classList.add(a);",
    "e.setAttribute('data-theme',p==='system'?a:p);",
    '}catch(_){}})();',
  ].join('');
};
