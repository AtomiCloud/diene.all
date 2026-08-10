import { isProblem, type Problem } from '@atomicloud/diene.problems';

/**
 * Content module — a React-free loading/error/empty/content (L/E/E) state
 * machine plus Problem integration and a framework-agnostic Problem-view
 * registry.
 *
 * The core is import-safe and SSR-safe: it never touches `window`, `document`,
 * timers, or any DOM global. Async orchestration is driven by an injected
 * source function, so behaviour is deterministic under test.
 */

/** Discriminated content state. */
export type ContentState<T> =
  | { readonly status: 'idle' }
  | { readonly status: 'loading' }
  | { readonly status: 'content'; readonly data: T }
  | { readonly status: 'empty'; readonly reason: string }
  | { readonly status: 'error'; readonly problem: Problem };

export type ContentStatus = ContentState<unknown>['status'];

/** Stable urn identifying the LocalError Problem produced from a raw throw. */
export const LOCAL_ERROR_TYPE = 'urn:atomicloud:frontend-utils:local-error';

/** The default empty reason surfaced when none is configured. */
export const DEFAULT_EMPTY_REASON = 'No content found';

/** Data payload attached to a LocalError Problem: message + captured stack. */
export interface LocalErrorData {
  readonly message: string;
  readonly name?: string;
  readonly stack?: string;
}

/** Type guard: is this Problem the LocalError wrapper produced by this module? */
export const isLocalError = (problem: Problem): problem is Problem<LocalErrorData> => problem.type === LOCAL_ERROR_TYPE;

const stringifyUnknown = (error: unknown): string => {
  if (typeof error === 'string') return error;
  try {
    return JSON.stringify(error) ?? String(error);
  } catch {
    return String(error);
  }
};

/**
 * Wrap any non-Problem throw into a LocalError {@link Problem}. The original
 * message and stacktrace are preserved verbatim in the Problem `data` so faro
 * (and the Problem visualizer) can surface a real trace.
 */
export const localErrorProblem = (error: unknown): Problem<LocalErrorData> => {
  if (error instanceof Error) {
    return {
      type: LOCAL_ERROR_TYPE,
      title: 'Local Error',
      status: 500,
      detail: error.message,
      data: { message: error.message, name: error.name, stack: error.stack },
    };
  }
  const message = stringifyUnknown(error);
  return {
    type: LOCAL_ERROR_TYPE,
    title: 'Local Error',
    status: 500,
    detail: message,
    data: { message },
  };
};

/** Normalise any thrown value into a Problem: Problems pass through, the rest wrap. */
export const toProblem = (error: unknown): Problem => (isProblem(error) ? error : localErrorProblem(error));

/**
 * Default emptiness predicate: an empty array or a nullish value is empty;
 * everything else is content.
 */
export const isEmptyContent = (value: unknown): boolean =>
  Array.isArray(value) ? value.length === 0 : value === null || value === undefined;

export interface ContentStateOptions<T> {
  /** Override emptiness detection. Defaults to {@link isEmptyContent}. */
  readonly emptyChecker?: (data: T) => boolean;
  /** Reason attached to the empty state. Defaults to {@link DEFAULT_EMPTY_REASON}. */
  readonly notFound?: string;
}

/** Pure transition: resolved data becomes either the content or the empty state. */
export const resolveContentState = <T>(data: T, options: ContentStateOptions<T> = {}): ContentState<T> => {
  const empty = (options.emptyChecker ?? isEmptyContent)(data);
  return empty ? { status: 'empty', reason: options.notFound ?? DEFAULT_EMPTY_REASON } : { status: 'content', data };
};

/** Pure transition: any thrown value becomes the error state carrying a Problem. */
export const errorContentState = <T>(error: unknown): ContentState<T> => ({
  status: 'error',
  problem: toProblem(error),
});

/** A content source resolves the value; it may be sync or async and may throw/reject. */
export type ContentSource<T> = () => T | Promise<T>;

export type ContentListener<T> = (state: ContentState<T>) => void;

export interface ContentStore<T> {
  readonly getState: () => ContentState<T>;
  readonly subscribe: (listener: ContentListener<T>) => () => void;
  /** Run a source; latest call wins — stale resolutions are discarded. */
  readonly load: (source: ContentSource<T>) => Promise<void>;
  readonly reset: () => void;
}

export interface ContentStoreOptions<T> extends ContentStateOptions<T> {
  readonly initial?: ContentState<T>;
}

/**
 * Create a subscribable L/E/E store. Concurrent {@link ContentStore.load} calls
 * are de-duplicated by an internal request id so a slow earlier request can
 * never overwrite a newer one (deterministic latest-wins).
 */
export const createContentStore = <T>(options: ContentStoreOptions<T> = {}): ContentStore<T> => {
  let state: ContentState<T> = options.initial ?? { status: 'idle' };
  let requestId = 0;
  const listeners = new Set<ContentListener<T>>();

  const set = (next: ContentState<T>): void => {
    state = next;
    for (const listener of listeners) listener(state);
  };

  return {
    getState: () => state,
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    async load(source) {
      const id = ++requestId;
      set({ status: 'loading' });
      try {
        const data = await source();
        if (id !== requestId) return;
        set(resolveContentState(data, options));
      } catch (error) {
        if (id !== requestId) return;
        set(errorContentState(error));
      }
    },
    reset() {
      set({ status: 'idle' });
    },
  };
};

/** A Problem view renders a Problem into some framework value `V` (e.g. ReactNode). */
export type ProblemView<V> = (problem: Problem) => V;

export interface ProblemViewRegistry<V> {
  /** Register (or replace) the view for a Problem `type`. */
  readonly register: (type: string, view: ProblemView<V>) => void;
  readonly has: (type: string) => boolean;
  /** Resolve the view for a Problem, falling back to the default view. */
  readonly resolve: (problem: Problem) => V;
}

/**
 * Framework-agnostic Problem-view registry. A default (fallback) view is
 * mandatory, so an unknown Problem type always renders a sane view — never
 * blank, never a crash. React binds this with `V = ReactNode`.
 */
export const createProblemViewRegistry = <V>(fallback: ProblemView<V>): ProblemViewRegistry<V> => {
  const views = new Map<string, ProblemView<V>>();
  return {
    register(type, view) {
      views.set(type, view);
    },
    has(type) {
      return views.has(type);
    },
    resolve(problem) {
      const view = views.get(problem.type) ?? fallback;
      return view(problem);
    },
  };
};
