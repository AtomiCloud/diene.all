/**
 * Minimal browser globals for the int tier: the storage, history, matchMedia,
 * and document-element surfaces the client adapters touch. Only the members
 * those adapters actually call are implemented — anything richer belongs to the
 * e2e tier, which runs a real browser.
 */
export interface FakeStorage {
  readonly getItem: (key: string) => string | null;
  readonly setItem: (key: string, value: string) => void;
  readonly removeItem: (key: string) => void;
  readonly map: Map<string, string>;
}

export const fakeStorage = (throws = false): FakeStorage => {
  const map = new Map<string, string>();
  const guard = (): void => {
    if (throws) throw new Error('storage unavailable');
  };
  return {
    getItem: key => {
      guard();
      return map.get(key) ?? null;
    },
    setItem: (key, value) => {
      guard();
      map.set(key, value);
    },
    removeItem: key => {
      guard();
      map.delete(key);
    },
    map,
  };
};

export interface FakeWindow {
  readonly listeners: Map<string, Set<(event?: unknown) => void>>;
  readonly emit: (type: string) => void;
  readonly timers: Map<number, () => void>;
  readonly flushTimers: () => void;
  readonly replaced: string[];
  readonly darkMedia: { matches: boolean; readonly emit: () => void };
}

/**
 * Install `window`/`document` doubles and return the handles a spec drives them
 * through. Returns a restore function; call it in `afterAll`.
 */
export const installBrowser = (
  storage: FakeStorage = fakeStorage(),
  search = '',
): { readonly handles: FakeWindow; readonly restore: () => void } => {
  const listeners = new Map<string, Set<(event?: unknown) => void>>();
  const timers = new Map<number, () => void>();
  const replaced: string[] = [];
  const mediaListeners = new Set<() => void>();
  let nextTimer = 1;
  const darkQuery = { matches: false };

  const darkMedia = {
    get matches() {
      return darkQuery.matches;
    },
    set matches(next: boolean) {
      darkQuery.matches = next;
    },
    emit: () => {
      for (const listener of mediaListeners) listener();
    },
  };

  const classes = new Set<string>();
  const documentElement = {
    style: { setProperty: (_name: string, _value: string) => undefined, removeProperty: () => undefined },
    classList: {
      toggle: (name: string, on: boolean) => {
        if (on) classes.add(name);
        else classes.delete(name);
      },
      has: (name: string) => classes.has(name),
    },
    dataset: {} as Record<string, string>,
  };

  const fakeWindow = {
    localStorage: storage,
    location: { search, pathname: '/', hash: '', href: `http://localhost/${search}` },
    history: { state: null, replaceState: (_s: unknown, _t: string, url: string) => replaced.push(url) },
    addEventListener: (type: string, listener: (event?: unknown) => void) => {
      const set = listeners.get(type) ?? new Set();
      set.add(listener);
      listeners.set(type, set);
    },
    removeEventListener: (type: string, listener: (event?: unknown) => void) => {
      listeners.get(type)?.delete(listener);
    },
    setTimeout: (fn: () => void) => {
      const handle = nextTimer;
      nextTimer += 1;
      timers.set(handle, fn);
      return handle;
    },
    clearTimeout: (handle: number) => {
      timers.delete(handle);
    },
    matchMedia: (query: string) => ({
      matches: query.includes('dark') ? darkQuery.matches : false,
      addEventListener: (_type: string, listener: () => void) => mediaListeners.add(listener),
      removeEventListener: (_type: string, listener: () => void) => mediaListeners.delete(listener),
    }),
    document: { documentElement },
  };

  const globals = globalThis as unknown as Record<string, unknown>;
  const previousWindow = globals['window'];
  const previousDocument = globals['document'];
  globals['window'] = fakeWindow;
  globals['document'] = { documentElement };

  return {
    handles: {
      listeners,
      emit: type => {
        for (const listener of listeners.get(type) ?? []) listener();
      },
      timers,
      flushTimers: () => {
        const pending = [...timers.entries()];
        timers.clear();
        for (const [, fn] of pending) fn();
      },
      replaced,
      darkMedia,
    },
    restore: () => {
      globals['window'] = previousWindow;
      globals['document'] = previousDocument;
    },
  };
};
