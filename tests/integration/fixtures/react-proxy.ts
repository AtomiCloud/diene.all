import * as RealReact from 'react';

/**
 * A call-time-delegating `react` stand-in for the int tier.
 *
 * `mock.module` is process-wide and modules cached while a substitute is
 * installed keep their bindings forever, so swapping the registration per file
 * cannot work: bun's test-file order is filesystem-dependent, and a component
 * first imported during a harness-era file stays bound to the harness stub
 * when a later file renders it through the real `react-dom/server`.
 *
 * Instead the preload registers THIS proxy exactly once, before any test file
 * loads. Every consumer — components, hooks, react-dom — binds to the proxy,
 * whose exports forward to the CURRENT implementation at call time. The hook
 * harness flips the target per file and flips it back in `afterAll`; cached
 * bindings stay correct in both modes because they only ever hold the proxy.
 *
 * The JSX runtimes are never substituted: the real ones are imported (and thus
 * cached, bound to the real React internals) before any mocking, so component
 * JSX always builds real elements — inert data under the harness, renderable
 * by `react-dom/server` everywhere else.
 */

type ReactModule = Record<string, unknown>;

let current: ReactModule = RealReact as unknown as ReactModule;

/** Swap the active implementation (the hook harness's mockReact/restoreReact). */
export const setReactImpl = (impl: ReactModule | undefined): void => {
  current = impl ?? (RealReact as unknown as ReactModule);
};

const forward =
  (name: string) =>
  (...args: unknown[]): unknown => {
    const target = current[name] ?? (RealReact as unknown as ReactModule)[name];
    return (target as (...a: unknown[]) => unknown)(...args);
  };

const buildProxy = (): ReactModule => {
  const proxy: ReactModule = {};
  for (const key of Object.keys(RealReact)) {
    const value = (RealReact as unknown as ReactModule)[key];
    if (typeof value === 'function') {
      proxy[key] = forward(key);
    } else {
      // Non-function exports (version, Fragment, shared internals) must be the
      // REAL values at bind time: react-dom validates `version` and the JSX
      // runtime resolves symbols through them. The harness never overrides these.
      proxy[key] = value;
    }
  }
  proxy['default'] = proxy;
  return proxy;
};

export const reactProxy: ReactModule = buildProxy();
