'use client';

import { createDraftStore, type ClearTrigger, type DraftStore } from '@atomicloud/diene.frontend-utils/persistence';
import { useEffect, useMemo, useState } from 'react';
import { buildDraftKey, shouldOfferRestore } from '@/lib/form-draft';

const browserStorage = {
  get: (key: string) => {
    try {
      return window.localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  set: (key: string, value: string) => {
    try {
      window.localStorage.setItem(key, value);
    } catch {
      // Draft persistence degrades silently without storage.
    }
  },
  remove: (key: string) => {
    try {
      window.localStorage.removeItem(key);
    } catch {
      // Ignore.
    }
  },
};

export interface FormDraftApi<T> {
  readonly values: T;
  readonly setValues: (patch: Partial<T>) => void;
  /** True when the mounted values came from a persisted draft. */
  readonly restored: boolean;
  /** Clear via one of the four terminal triggers (submit/reset/cancel/close). */
  readonly clear: (trigger: ClearTrigger) => void;
}

/**
 * Form drafts (product-thoughtfulness #2): values persist to localStorage as
 * the user types and survive refresh/accidental dismissal; the four terminal
 * triggers clear them (clear-on-submit is the form-lifecycle gate's journey).
 */
export function useFormDraft<T extends Record<string, unknown>>(key: string, initial: T): FormDraftApi<T> {
  const store = useMemo<DraftStore<T>>(
    () => createDraftStore<T>({ key: buildDraftKey(key), storage: browserStorage }),
    [key],
  );
  const [values, setState] = useState<T>(initial);
  const [restored, setRestored] = useState(false);

  useEffect(() => {
    const draft = store.load();
    if (draft !== undefined && shouldOfferRestore(draft)) {
      setState(draft);
      setRestored(true);
    }
  }, [store]);

  return {
    values,
    restored,
    setValues: patch =>
      setState(previous => {
        const next = { ...previous, ...patch };
        store.save(next);
        return next;
      }),
    clear: trigger => {
      store.clear(trigger);
      setState(initial);
      setRestored(false);
    },
  };
}
