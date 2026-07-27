import { mock } from 'bun:test';

/**
 * In-memory stand-in for the Next.js cookie jar. `next/headers` is only
 * available inside a request scope, so the int tier substitutes this jar and
 * exercises the real adapters against it.
 */
export interface FakeJar {
  readonly get: (name: string) => { readonly name: string; readonly value: string } | undefined;
  readonly set: (name: string, value: string, options?: unknown) => void;
  readonly delete: (name: string) => void;
  /** Test-only escape hatch: the raw store, so specs can seed or assert directly. */
  readonly store: Map<string, string>;
}

export const fakeJar = (seed: Readonly<Record<string, string>> = {}): FakeJar => {
  const store = new Map<string, string>(Object.entries(seed));
  return {
    get: name => (store.has(name) ? { name, value: store.get(name) ?? '' } : undefined),
    set: (name, value) => {
      store.set(name, value);
    },
    delete: name => {
      store.delete(name);
    },
    store,
  };
};

/**
 * Install a module mock for `next/headers` whose `cookies()` resolves to `jar`.
 * Call before importing any server adapter under test.
 */
export const mockCookies = (jar: FakeJar): void => {
  mock.module('next/headers', () => ({
    cookies: async () => jar,
    headers: async () => new Headers(),
  }));
};
