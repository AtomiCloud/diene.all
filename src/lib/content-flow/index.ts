import {
  DEFAULT_EMPTY_REASON,
  isEmptyContent,
  type ContentSource,
  type ContentState,
  type ContentStore,
} from '@atomicloud/diene.frontend-utils/content';

/**
 * The template's content flow: the ONE place this app decides what "empty"
 * means and how a resolved payload becomes a terminal L/E/E state.
 *
 * The lib owns the store (subscription, latest-wins de-duplication, Problem
 * wrapping); this layer owns the app's emptiness POLICY, so it stays pure,
 * node-safe, and unit-covered independently of React and of however the store
 * was constructed.
 */

/** The flow's emptiness predicate — the single decision point for empty. */
export const isEmptyFlowResult = (value: unknown): boolean => isEmptyContent(value);

/**
 * Drive a content store through a source and return the terminal state.
 *
 * A payload the store accepted as content is re-checked against the flow's own
 * emptiness policy, so an empty payload can never reach the content branch even
 * when the store was created without an empty checker.
 */
export const runContentFlow = async <T>(
  store: ContentStore<T>,
  source: ContentSource<T>,
  notFound: string = DEFAULT_EMPTY_REASON,
): Promise<ContentState<T>> => {
  await store.load(source);
  const state = store.getState();
  if (state.status === 'empty') return { status: 'empty', reason: notFound };
  if (state.status === 'content' && isEmptyFlowResult(state.data)) {
    return { status: 'empty', reason: notFound };
  }
  return state;
};
