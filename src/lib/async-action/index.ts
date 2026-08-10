/**
 * Click-reaction guard (product-thoughtfulness #4) as a pure state machine: an
 * async trigger admits exactly one in-flight run, so a double click can never
 * double-submit. React only owns the rendering; the admission decision lives
 * here, node-safe and unit-covered.
 */

export interface AsyncActionState {
  readonly pending: boolean;
}

/** The idle starting state — nothing in flight. */
export const idleAction: AsyncActionState = { pending: false };

/** True while a run is in flight. */
export const isPending = (state: AsyncActionState): boolean => state.pending;

export interface BeginOutcome {
  /** False when a run is already in flight — the caller must not start another. */
  readonly admitted: boolean;
  readonly state: AsyncActionState;
}

/**
 * Attempt to begin a run. Admission is refused while one is already in flight;
 * the returned state is the one the caller must keep.
 */
export const begin = (state: AsyncActionState): BeginOutcome =>
  isPending(state) ? { admitted: false, state } : { admitted: true, state: { pending: true } };

/** Settle the in-flight run (success or failure alike) and return to idle. */
export const settle = (_state: AsyncActionState): AsyncActionState => idleAction;
