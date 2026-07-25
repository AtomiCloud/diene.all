'use client';

import { useCallback, useRef, useState } from 'react';
import { begin, idleAction, isPending, settle, type AsyncActionState } from '@/lib/async-action';

export interface AsyncActionApi {
  readonly pending: boolean;
  readonly run: () => void;
}

/**
 * Click-reaction wrapper (product-thoughtfulness #4): an async trigger
 * disables itself and shows pending state until the action settles — no dead
 * clicks, no double-submit. The re-entrancy decision is the pure state machine
 * in `src/lib/async-action`; this hook only mirrors it into React state.
 */
export function useAsyncAction(action: () => Promise<void>): AsyncActionApi {
  const [pending, setPending] = useState(false);
  const machine = useRef<AsyncActionState>(idleAction);

  const run = useCallback(() => {
    const outcome = begin(machine.current);
    if (!outcome.admitted) return;
    machine.current = outcome.state;
    setPending(isPending(outcome.state));
    void action().finally(() => {
      machine.current = settle(machine.current);
      setPending(isPending(machine.current));
    });
  }, [action]);

  return { pending, run };
}
