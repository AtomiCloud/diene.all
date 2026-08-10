import { describe, it } from 'bun:test';
import should from 'should';
import {
  type Appearance,
  createCssVariableApplier,
  createThemeStore,
  DEFAULT_THEME_STORAGE_KEY,
  type ResolvedTheme,
  resolveTheme,
  type SystemAppearancePort,
  type ThemeApplierPort,
  type ThemeStoragePort,
  themeInitScript,
} from '../../src/lib/theme/index';

const fakeStorage = (initial: Record<string, string> = {}) => {
  const map = new Map<string, string>(Object.entries(initial));
  const port: ThemeStoragePort = {
    get: key => map.get(key) ?? null,
    set: (key, value) => {
      map.set(key, value);
    },
  };
  return { port, map };
};

const fakeSystem = (initial: Appearance) => {
  let appearance = initial;
  const listeners = new Set<(a: Appearance) => void>();
  const port: SystemAppearancePort = {
    get: () => appearance,
    subscribe: listener => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
  };
  const emit = (next: Appearance) => {
    appearance = next;
    for (const listener of listeners) listener(next);
  };
  return { port, emit, listenerCount: () => listeners.size };
};

const recordingApplier = () => {
  const applied: ResolvedTheme[] = [];
  const port: ThemeApplierPort = { apply: resolved => applied.push(resolved) };
  return { port, applied };
};

const namedConfig = { themes: { midnight: 'dark' as Appearance }, fallback: 'light' };

describe('theme · resolveTheme', () => {
  it('should map system to the current appearance', () => {
    should(resolveTheme('system', 'dark')).deepEqual({ preference: 'system', name: 'dark', appearance: 'dark' });
  });

  it('should resolve the built-in light and dark preferences', () => {
    should(resolveTheme('light', 'dark')).deepEqual({ preference: 'light', name: 'light', appearance: 'light' });
    should(resolveTheme('dark', 'light')).deepEqual({ preference: 'dark', name: 'dark', appearance: 'dark' });
  });

  it('should resolve a named theme to its configured appearance', () => {
    should(resolveTheme('midnight', 'light', namedConfig)).deepEqual({
      preference: 'midnight',
      name: 'midnight',
      appearance: 'dark',
    });
  });

  it('should fall back to a known fallback preference for unknown input', () => {
    should(resolveTheme('bogus', 'dark', namedConfig)).deepEqual({
      preference: 'light',
      name: 'light',
      appearance: 'light',
    });
  });

  it('should degrade to system when the fallback defaults to system', () => {
    should(resolveTheme('bogus', 'dark')).deepEqual({ preference: 'system', name: 'dark', appearance: 'dark' });
  });

  it('should degrade to system when the configured fallback is itself unknown', () => {
    should(resolveTheme('bogus', 'light', { fallback: 'also-bogus' })).deepEqual({
      preference: 'system',
      name: 'light',
      appearance: 'light',
    });
  });
});

describe('theme · store', () => {
  it('should read the persisted preference and apply once on construction', () => {
    // Arrange
    const storage = fakeStorage({ [DEFAULT_THEME_STORAGE_KEY]: 'dark' });
    const system = fakeSystem('light');
    const applier = recordingApplier();

    // Act
    const store = createThemeStore({ storage: storage.port, system: system.port, applier: applier.port });

    // Assert
    should(store.getPreference()).equal('dark');
    should(store.getResolved().appearance).equal('dark');
    should(applier.applied).have.length(1);
  });

  it('should default to system when nothing is persisted', () => {
    // Arrange
    const storage = fakeStorage();
    const system = fakeSystem('dark');
    const applier = recordingApplier();

    // Act
    const store = createThemeStore({ storage: storage.port, system: system.port, applier: applier.port });

    // Assert
    should(store.getPreference()).equal('system');
    should(store.getResolved().appearance).equal('dark');
  });

  it('should persist and re-apply on setTheme and notify subscribers', () => {
    // Arrange
    const storage = fakeStorage();
    const system = fakeSystem('light');
    const applier = recordingApplier();
    const store = createThemeStore({
      storage: storage.port,
      system: system.port,
      applier: applier.port,
      storageKey: 'ui.theme',
    });
    const seen: ResolvedTheme[] = [];
    const unsubscribe = store.subscribe(resolved => seen.push(resolved));

    // Act
    store.setTheme('dark');

    // Assert
    should(storage.map.get('ui.theme')).equal('dark');
    should(store.getResolved().appearance).equal('dark');
    should(seen).have.length(1);
    should(applier.applied.at(-1)?.appearance).equal('dark');

    // Act — round-trip: a fresh store reads the persisted value
    const reloaded = createThemeStore({
      storage: storage.port,
      system: system.port,
      applier: recordingApplier().port,
      storageKey: 'ui.theme',
    });
    should(reloaded.getPreference()).equal('dark');

    unsubscribe();
    store.setTheme('light');
    should(seen).have.length(1);
  });

  it('should re-resolve when the system appearance changes', () => {
    // Arrange
    const storage = fakeStorage();
    const system = fakeSystem('light');
    const applier = recordingApplier();
    const store = createThemeStore({ storage: storage.port, system: system.port, applier: applier.port });

    // Act
    system.emit('dark');

    // Assert
    should(store.getResolved().appearance).equal('dark');
  });

  it('should release the system subscription and listeners on destroy', () => {
    // Arrange
    const storage = fakeStorage();
    const system = fakeSystem('light');
    const applier = recordingApplier();
    const store = createThemeStore({ storage: storage.port, system: system.port, applier: applier.port });
    let notified = 0;
    store.subscribe(() => {
      notified += 1;
    });

    // Act
    store.destroy();
    system.emit('dark');

    // Assert
    should(system.listenerCount()).equal(0);
    should(notified).equal(0);
  });

  it('should switch consumer-authored CSS variables and remove stale values', () => {
    // Arrange
    const variables = new Map<string, string>();
    const applier = createCssVariableApplier(
      {
        setProperty: (name, value) => {
          variables.set(name, value);
        },
        removeProperty: name => {
          variables.delete(name);
        },
      },
      {
        light: { '--surface': '#fff', '--ink': '#111' },
        dark: { '--surface': '#111' },
      },
    );
    const store = createThemeStore({
      storage: fakeStorage({ theme: 'light' }).port,
      system: fakeSystem('light').port,
      applier,
    });

    // Act
    store.setTheme('dark');

    // Assert
    should(Object.fromEntries(variables)).deepEqual({ '--surface': '#111' });
  });
});

describe('theme · init script', () => {
  it('should build a self-contained no-flash script with the default key', () => {
    // Act
    const script = themeInitScript();

    // Assert
    should(script).containEql('localStorage.getItem');
    should(script).containEql('prefers-color-scheme: dark');
    should(script).containEql(JSON.stringify(DEFAULT_THEME_STORAGE_KEY));
    should(script).containEql('data-theme');
  });

  it('should bake a custom key and named-theme map', () => {
    // Act
    const script = themeInitScript({ storageKey: 'ui.theme', themes: { midnight: 'dark' } });

    // Assert
    should(script).containEql('"ui.theme"');
    should(script).containEql('"midnight":"dark"');
  });
});
