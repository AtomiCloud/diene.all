/**
 * URL-state module — real-time URL ↔ state synchronisation.
 *
 * Server-reads-on-load: {@link readUrlState} hydrates state from the request's
 * search params. Client-updates-on-interaction: {@link createUrlStateController}
 * mirrors state into the URL with a debounced `replaceState` — NEVER a
 * pushState-per-keystroke. The core is React-free and SSR-safe; history and
 * timers are behind injected ports.
 */

export const DEFAULT_URLSTATE_DEBOUNCE_MS = 300;

/** Any shape the server can hand us for the current query. */
export type UrlStateSource = URLSearchParams | string | Readonly<Record<string, string | string[] | undefined>>;

const firstValue = (value: string | string[] | undefined): string | undefined =>
  Array.isArray(value) ? value[0] : value;

const readParam = (source: UrlStateSource, key: string): string | undefined => {
  if (typeof source === 'string') return new URLSearchParams(source).get(key) ?? undefined;
  if (source instanceof URLSearchParams) return source.get(key) ?? undefined;
  return firstValue(source[key]);
};

/**
 * Merge a query source over defaults. Present params win; absent keys keep
 * their default. Deterministic and side-effect free.
 */
export const readUrlState = <T extends Record<string, string>>(source: UrlStateSource, defaults: T): T => {
  const result: Record<string, string> = {};
  for (const [key, fallback] of Object.entries(defaults)) {
    result[key] = readParam(source, key) ?? fallback;
  }
  return result as T;
};

/**
 * Serialise state into a query string, omitting any value equal to its default
 * so URLs stay clean and round-trip through {@link readUrlState}.
 */
export const serializeUrlState = <T extends Record<string, string>>(state: T, defaults: T): string => {
  const params = new URLSearchParams();
  for (const key of Object.keys(state)) {
    const value = state[key];
    if (value === undefined) continue;
    if (value === defaults[key]) continue;
    params.set(key, value);
  }
  return params.toString();
};

/** Compute the next `?search` string (empty string when nothing differs). */
export const computeNextSearch = <T extends Record<string, string>>(state: T, defaults: T): string => {
  const query = serializeUrlState(state, defaults);
  return query ? `?${query}` : '';
};

/** Opaque timer handle produced by the scheduler port. */
export type TimerHandle = unknown;

export interface SchedulerPort {
  readonly setTimer: (fn: () => void, ms: number) => TimerHandle;
  readonly clearTimer: (handle: TimerHandle) => void;
}

/** Port that mirrors state into the address bar. Only `replaceState` — never push. */
export interface HistoryPort {
  readonly replaceState: (search: string) => void;
}

export type UrlStateListener<T> = (state: T) => void;

export interface UrlStateController<T> {
  readonly getState: () => T;
  /** Merge a patch, emit immediately, and debounce the URL sync. */
  readonly setState: (patch: Partial<T>) => void;
  readonly subscribe: (listener: UrlStateListener<T>) => () => void;
  /** Cancel any pending debounce and sync the URL now. */
  readonly flush: () => void;
  /** Cancel any pending debounce and drop listeners. */
  readonly destroy: () => void;
}

export interface UrlStateControllerOptions<T extends Record<string, string>> {
  readonly defaults: T;
  readonly history: HistoryPort;
  readonly scheduler: SchedulerPort;
  readonly initial?: Partial<T>;
  readonly debounceMs?: number;
}

/**
 * Create a client-side URL-state controller. Interaction updates local state
 * synchronously (responsive UI) and schedule a single trailing `replaceState`;
 * rapid updates coalesce into one history write.
 */
export const createUrlStateController = <T extends Record<string, string>>(
  options: UrlStateControllerOptions<T>,
): UrlStateController<T> => {
  const debounceMs = options.debounceMs ?? DEFAULT_URLSTATE_DEBOUNCE_MS;
  const listeners = new Set<UrlStateListener<T>>();
  let state: T = { ...options.defaults, ...options.initial };
  let timer: TimerHandle | null = null;

  const cancel = (): void => {
    if (timer !== null) {
      options.scheduler.clearTimer(timer);
      timer = null;
    }
  };

  const sync = (): void => {
    options.history.replaceState(computeNextSearch(state, options.defaults));
  };

  return {
    getState: () => state,
    setState(patch) {
      state = { ...state, ...patch };
      for (const listener of listeners) listener(state);
      cancel();
      if (debounceMs > 0) {
        timer = options.scheduler.setTimer(() => {
          timer = null;
          sync();
        }, debounceMs);
      } else {
        sync();
      }
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    flush() {
      cancel();
      sync();
    },
    destroy() {
      cancel();
      listeners.clear();
    },
  };
};
