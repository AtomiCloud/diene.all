import type { Problem } from '@atomicloud/diene.problems';
import { type ReactNode, useSyncExternalStore } from 'react';
import type { ContentState, ContentStore, ProblemViewRegistry } from '../lib/content/index.js';

/**
 * React binding for the content L/E/E state machine.
 *
 * Thin adapter only: it subscribes to a {@link ContentStore} (created with the
 * React-free core) and renders the branch for the current state. All loading
 * logic lives in the core; this layer just maps state → ReactNode.
 */

/** Renderers for each content branch. `idle` is optional (defaults to nothing). */
export interface ContentBranches<T> {
  readonly idle?: () => ReactNode;
  readonly loading: () => ReactNode;
  readonly empty: (reason: string) => ReactNode;
  readonly error: (problem: Problem) => ReactNode;
  readonly content: (data: T) => ReactNode;
}

/** Pure state → node mapping, exhaustive over every content status. */
export const renderContentState = <T,>(state: ContentState<T>, branches: ContentBranches<T>): ReactNode => {
  switch (state.status) {
    case 'idle':
      return branches.idle?.() ?? null;
    case 'loading':
      return branches.loading();
    case 'empty':
      return branches.empty(state.reason);
    case 'error':
      return branches.error(state.problem);
    case 'content':
      return branches.content(state.data);
  }
};

/** Subscribe to a content store and return its current state (SSR-safe snapshot). */
export const useContentStore = <T,>(store: ContentStore<T>): ContentState<T> =>
  useSyncExternalStore(store.subscribe, store.getState, store.getState);

export interface ContentProps<T> extends ContentBranches<T> {
  readonly store: ContentStore<T>;
}

/** Component form: subscribe to `store` and render the active branch. */
export const Content = <T,>({ store, ...branches }: ContentProps<T>): ReactNode =>
  renderContentState(useContentStore(store), branches);

export interface ProblemViewProps {
  readonly registry: ProblemViewRegistry<ReactNode>;
  readonly problem: Problem;
}

/** Render any Problem through the registry (default view for unknown types). */
export const ProblemView = ({ registry, problem }: ProblemViewProps): ReactNode => registry.resolve(problem);
