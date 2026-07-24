import type { PropsWithChildren, ReactNode } from 'react';
import { type ContentState, localErrorProblem } from '../lib/content/index.js';
import {
  type KnownLandscape,
  type LandscapeSource,
  SERVING_LANDSCAPE_FIXTURES,
  WORKLOAD_LANDSCAPES,
} from '../lib/landscape/index.js';
import { createModuleRegistry, type ModuleRegistry } from '../lib/module/index.js';

export const landscapeFixtures = {
  binding: (value: KnownLandscape): LandscapeSource => ({ source: 'binding', value }),
  bakedConstant: (value: KnownLandscape): LandscapeSource => ({ source: 'baked-constant', value }),
  dartDefine: (value: KnownLandscape): LandscapeSource => ({ source: 'dart-define', value }),
};

export const landscapeFixtureMatrix = [...WORKLOAD_LANDSCAPES, ...SERVING_LANDSCAPE_FIXTURES] as const;

export interface MemoryPersistence {
  readonly length: number;
  clear(): void;
  get(key: string): string | null;
  getItem(key: string): string | null;
  key(index: number): string | null;
  remove(key: string): void;
  removeItem(key: string): void;
  set(key: string, value: string): void;
  setItem(key: string, value: string): void;
  snapshot(): Readonly<Record<string, string>>;
}

export const createInMemoryPersistence = (initial: Readonly<Record<string, string>> = {}): MemoryPersistence => {
  const values = new Map(Object.entries(initial));
  return {
    get length() {
      return values.size;
    },
    clear() {
      values.clear();
    },
    get(key) {
      return values.get(key) ?? null;
    },
    getItem(key) {
      return values.get(key) ?? null;
    },
    key(index) {
      return [...values.keys()][index] ?? null;
    },
    remove(key) {
      values.delete(key);
    },
    removeItem(key) {
      values.delete(key);
    },
    set(key, value) {
      values.set(key, value);
    },
    setItem(key, value) {
      values.set(key, value);
    },
    snapshot() {
      return Object.freeze(Object.fromEntries(values));
    },
  };
};

export interface ProviderPins {
  readonly landscape: LandscapeSource;
  readonly theme: string;
}

export interface ProviderHarness {
  readonly pins: ProviderPins;
  readonly Wrapper: (props: PropsWithChildren) => ReactNode;
}

export const createPinnedProviderHarness = (
  pins: ProviderPins,
  render: (pins: ProviderPins, children: ReactNode) => ReactNode,
): ProviderHarness => ({
  pins: Object.freeze(pins),
  Wrapper: ({ children }) => render(pins, children),
});

export const createFakeModuleRegistry = (): ModuleRegistry => createModuleRegistry();

export const contentStates = {
  idle: <T>(): ContentState<T> => ({ status: 'idle' }),
  loading: <T>(): ContentState<T> => ({ status: 'loading' }),
  empty: <T>(reason = 'No content found'): ContentState<T> => ({ status: 'empty', reason }),
  content: <T>(data: T): ContentState<T> => ({ status: 'content', data }),
  error: <T>(error: unknown): ContentState<T> => ({
    status: 'error',
    problem: localErrorProblem(error),
  }),
};
