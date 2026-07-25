'use client';

import { useCallback, useRef, useState } from 'react';

export interface AsyncActionApi {
  readonly pending: boolean;
  readonly run: () => void;
}

/**
 * Click-reaction wrapper (product-thoughtfulness #4): an async trigger
 * disables itself and shows pending state until the action settles — no dead
 * clicks, no double-submit. Re-entrancy is blocked while in flight.
 */
export function useAsyncAction(action: () => Promise<void>): AsyncActionApi {
  const [pending, setPending] = useState(false);
  const inFlight = useRef(false);

  const run = useCallback(() => {
    if (inFlight.current) return;
    inFlight.current = true;
    setPending(true);
    void action().finally(() => {
      inFlight.current = false;
      setPending(false);
    });
  }, [action]);

  return { pending, run };
}
