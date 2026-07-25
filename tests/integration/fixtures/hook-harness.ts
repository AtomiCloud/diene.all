import { mock } from 'bun:test';
import { reactProxy, setReactImpl } from './react-proxy';

// Register the call-time-delegating proxy ONCE, at first harness import
// (mock.module deadlocks inside the preload, so it lives here). Modules loaded
// before this point bound the real react — correct; modules loaded after bind
// the proxy, which forwards to the real react whenever no stub is active, so
// bun's filesystem-dependent file order can no longer leak the stub into a
// react-dom/server spec.
mock.module('react', () => reactProxy);

/**
 * Dependency-free hook harness for the int tier.
 *
 * A React hook is a function of the React primitives it calls, so substituting
 * a synchronous implementation of those primitives runs the hook's REAL code
 * without a renderer or a DOM-emulation dependency. Effects run at the end of
 * each render pass and a state update re-renders synchronously, which is what
 * the adapters under test actually depend on.
 *
 * Browser behaviour proper (paint, focus, history) is the e2e tier's job — this
 * harness only proves the adapter's own wiring.
 */
export interface Harness<T> {
  /** The hook's most recent return value. */
  readonly current: () => T;
  /** Re-run the hook, flushing effects. Use after driving an external source. */
  readonly rerender: () => void;
  /** Run every registered cleanup, as unmount would. */
  readonly unmount: () => void;
}

interface Cell {
  value: unknown;
  deps?: readonly unknown[];
  cleanup?: (() => void) | void;
}

/**
 * Install the synchronous React substitute. Call once, before importing hooks.
 * The JSX runtimes go with it: React's dev runtime reads shared internals that
 * only exist in the real module, so a component's JSX must build inert
 * descriptors instead. Effects still run; children are never rendered.
 */
export const mockReact = (): void => {
  setReactImpl(reactStub);
};

/**
 * Point the react proxy back at the real implementation. Every harness file
 * MUST call this from `afterAll` — the proxy is process-wide and bun's test
 * file order is filesystem-dependent, so a leaked stub breaks whichever
 * react-dom/server spec happens to run later.
 */
export const restoreReact = (): void => {
  setReactImpl(undefined);
};

let cells: Cell[] = [];
let cursor = 0;
let effects: { readonly run: () => void; readonly index: number; readonly deps?: readonly unknown[] }[] = [];
let scheduleRender: (() => void) | undefined;

const cell = (init: () => Cell): Cell => {
  cells[cursor] ??= init();
  const found = cells[cursor] as Cell;
  cursor += 1;
  return found;
};

const changed = (previous: readonly unknown[] | undefined, next: readonly unknown[] | undefined): boolean =>
  previous === undefined ||
  next === undefined ||
  next.length !== previous.length ||
  next.some((d, i) => d !== previous[i]);

const useState = <S>(initial: S | (() => S)): [S, (next: S | ((previous: S) => S)) => void] => {
  const slot = cell(() => ({ value: typeof initial === 'function' ? (initial as () => S)() : initial }));
  const set = (next: S | ((previous: S) => S)): void => {
    const resolved = typeof next === 'function' ? (next as (previous: S) => S)(slot.value as S) : next;
    if (resolved === slot.value) return;
    slot.value = resolved;
    scheduleRender?.();
  };
  return [slot.value as S, set];
};

const useRef = <S>(initial: S): { current: S } => cell(() => ({ value: { current: initial } })).value as { current: S };

const useMemo = <S>(factory: () => S, deps?: readonly unknown[]): S => {
  let fresh = false;
  const slot = cell(() => {
    fresh = true;
    return { value: factory(), deps };
  });
  if (!fresh && changed(slot.deps, deps)) {
    slot.value = factory();
    slot.deps = deps;
  }
  return slot.value as S;
};

const useCallback = <S>(fn: S, deps?: readonly unknown[]): S => useMemo(() => fn, deps);

const useEffect = (run: () => (() => void) | void, deps?: readonly unknown[]): void => {
  const index = cursor;
  cell(() => ({ value: undefined, deps: undefined }));
  effects.push({ run: run as () => void, index, deps });
};

// Enough of the element/context surface for a client component to be CALLED as
// a hook: its effects run, its children are never rendered. Proving what the
// markup looks like is the e2e tier's job.
const contexts = new WeakMap<object, { value: unknown }>();

const createContext = <S>(initial: S): { Provider: unknown; _current: S } => {
  const context = { Provider: (props: unknown) => props, _current: initial };
  contexts.set(context, { value: initial });
  return context;
};

const useContext = <S>(context: { _current: S }): S => context._current;

const createElement = (type: unknown, props: unknown, ...children: unknown[]): unknown => ({
  type,
  props: { ...(props as object), children },
});

/** Store subscription primitive, as the frontend-utils react bindings use it. */
const useSyncExternalStore = <S>(subscribe: (onChange: () => void) => () => void, getSnapshot: () => S): S => {
  const [snapshot, setSnapshot] = useState(getSnapshot());
  useEffect(() => subscribe(() => setSnapshot(getSnapshot())), [subscribe, getSnapshot]);
  return snapshot;
};

const primitives = {
  useState,
  useRef,
  useMemo,
  useCallback,
  useEffect,
  useLayoutEffect: useEffect,
  useInsertionEffect: useEffect,
  useDebugValue: () => undefined,
  useId: () => 'harness-id',
  useReducer: <S, A>(reducer: (state: S, action: A) => S, initial: S): [S, (action: A) => void] => {
    const [state, set] = useState(initial);
    return [state, (action: A) => set(previous => reducer(previous, action))];
  },
  useSyncExternalStore,
  useTransition: (): [boolean, (fn: () => void) => void] => [false, (fn: () => void) => fn()],
  createContext,
  useContext,
  createElement,
  Fragment: 'fragment',
};

const reactStub = { ...primitives, default: primitives };

/** Render `hook` under the harness, flushing effects and state-driven re-renders. */
export const renderHook = <T>(hook: () => T): Harness<T> => {
  const own: Cell[] = [];
  let latest: T;
  let rendering = false;
  let queued = false;

  // One render pass: run the hook, then flush the effects whose deps changed.
  // Effect deps are recorded BEFORE the effect body runs, so a state update from
  // inside an effect re-renders without re-running that same effect.
  const once = (): void => {
    cells = own;
    cursor = 0;
    effects = [];
    latest = hook();
    for (const effect of effects) {
      const slot = own[effect.index] as Cell;
      if (!changed(slot.deps, effect.deps)) continue;
      slot.deps = effect.deps;
      slot.cleanup?.();
      slot.cleanup = effect.run() as (() => void) | void;
    }
  };

  // State updates queue another pass rather than recursing, mirroring React's
  // batching closely enough that a settled hook settles here too.
  const pass = (): void => {
    if (rendering) {
      queued = true;
      return;
    }
    rendering = true;
    try {
      let guard = 0;
      do {
        queued = false;
        guard += 1;
        if (guard > 50) throw new Error('hook harness: render loop did not settle');
        once();
      } while (queued);
    } finally {
      rendering = false;
    }
  };

  scheduleRender = pass;
  pass();

  return {
    current: () => latest,
    rerender: pass,
    unmount: () => {
      for (const slot of own) slot?.cleanup?.();
      scheduleRender = undefined;
    },
  };
};
