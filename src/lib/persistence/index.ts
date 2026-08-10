/**
 * Form-persistence module — localStorage-backed form drafts.
 *
 * Drafts are saved as the user types and CLEARED on the four terminal triggers
 * (cancel/close/submit/reset). An accidental dismissal (backdrop tap / back
 * gesture) does NOT clear the draft; instead the draft is returned so the UI can
 * offer to restore it. The core is React-free and SSR-safe: storage is an
 * injected port and malformed persisted data is tolerated.
 */

/** The four terminal triggers that clear a draft. */
export type ClearTrigger = 'cancel' | 'close' | 'submit' | 'reset';

/** Accidental-dismissal reasons that PRESERVE the draft for a restore offer. */
export type DismissReason = 'backdrop' | 'back';

export const CLEAR_TRIGGERS: readonly ClearTrigger[] = ['cancel', 'close', 'submit', 'reset'];

/** Read/write/remove port for persisted drafts (e.g. localStorage). */
export interface DraftStoragePort {
  readonly get: (key: string) => string | null;
  readonly set: (key: string, value: string) => void;
  readonly remove: (key: string) => void;
}

export interface DraftStore<T> {
  readonly save: (draft: T) => void;
  /** Return the persisted draft, or `undefined` when absent or malformed. */
  readonly load: () => T | undefined;
  readonly has: () => boolean;
  /** Remove the draft in response to a terminal trigger. */
  readonly clear: (trigger: ClearTrigger) => void;
  /** Accidental dismissal: keep the draft and return it for a restore offer. */
  readonly dismiss: (reason: DismissReason) => T | undefined;
}

export interface DraftStoreOptions<T> {
  /** Namespaced storage key. */
  readonly key: string;
  readonly storage: DraftStoragePort;
  /** Notified when a terminal trigger clears the draft. */
  readonly onCleared?: (trigger: ClearTrigger) => void;
  /** Notified when an accidental dismissal offers a restore. */
  readonly onRestoreOffer?: (reason: DismissReason, draft: T) => void;
}

/**
 * Create a draft store bound to a single namespaced key. Reads never throw:
 * malformed JSON resolves to `undefined` (treated as "no draft").
 */
export const createDraftStore = <T>(options: DraftStoreOptions<T>): DraftStore<T> => {
  const { key, storage } = options;

  const load = (): T | undefined => {
    const raw = storage.get(key);
    if (raw === null) return undefined;
    try {
      return JSON.parse(raw) as T;
    } catch {
      return undefined;
    }
  };

  return {
    save(draft) {
      storage.set(key, JSON.stringify(draft));
    },
    load,
    has() {
      return load() !== undefined;
    },
    clear(trigger) {
      storage.remove(key);
      options.onCleared?.(trigger);
    },
    dismiss(reason) {
      const draft = load();
      if (draft !== undefined) options.onRestoreOffer?.(reason, draft);
      return draft;
    },
  };
};
