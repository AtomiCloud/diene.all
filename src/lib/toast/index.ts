/**
 * Toast module — passive, accessible notification lifecycle.
 *
 * Toasts are PASSIVE only: they carry non-error severities and are announced
 * with `aria-live="polite"`, never `assertive`. Errors must NOT be shown as
 * toasts (surface them through the Problem visualizer instead). Every toast
 * dwells for at least 5s. The core is React-free and SSR-safe; timing is behind
 * an injected scheduler port.
 */

/** Passive severities — deliberately excludes `error`. */
export type ToastSeverity = 'info' | 'success' | 'warning';

export const PASSIVE_SEVERITIES: readonly ToastSeverity[] = ['info', 'success', 'warning'];

/** Minimum dwell time; requests below this are clamped up. */
export const MIN_TOAST_DWELL_MS = 5000;

/** Passive toasts announce politely — never assertively. */
export type AriaLive = 'polite';

/** Opaque timer handle produced by the scheduler port. */
export type TimerHandle = unknown;

export interface SchedulerPort {
  readonly setTimer: (fn: () => void, ms: number) => TimerHandle;
  readonly clearTimer: (handle: TimerHandle) => void;
}

export interface ToastInput {
  readonly message: string;
  readonly severity?: ToastSeverity;
  /** Requested dwell; clamped to at least {@link MIN_TOAST_DWELL_MS}. */
  readonly durationMs?: number;
}

export interface Toast {
  readonly id: string;
  readonly message: string;
  readonly severity: ToastSeverity;
  readonly durationMs: number;
  readonly ariaLive: AriaLive;
}

export type ToastListener = (toasts: readonly Toast[]) => void;

export interface ToastStore {
  readonly getToasts: () => readonly Toast[];
  readonly show: (input: ToastInput) => Toast;
  readonly dismiss: (id: string) => void;
  readonly subscribe: (listener: ToastListener) => () => void;
  readonly destroy: () => void;
}

export interface ToastStoreOptions {
  readonly scheduler: SchedulerPort;
  /** Deterministic id generator; defaults to a monotonic counter. */
  readonly idFactory?: () => string;
}

/** Runtime guard rejecting error/assertive misuse of the passive toast channel. */
export function assertPassiveSeverity(severity: string): asserts severity is ToastSeverity {
  if (!PASSIVE_SEVERITIES.includes(severity as ToastSeverity)) {
    throw new TypeError(`toast severity "${severity}" is not passive; toasts must not be used for errors`);
  }
}

const defaultIdFactory = (): (() => string) => {
  let counter = 0;
  return () => `toast-${++counter}`;
};

/**
 * Create a toast store. Each shown toast is auto-dismissed after its (clamped)
 * dwell via the scheduler; {@link ToastStore.dismiss} removes it early and
 * cancels the timer. {@link ToastStore.destroy} clears all timers and toasts.
 */
export const createToastStore = (options: ToastStoreOptions): ToastStore => {
  const nextId = options.idFactory ?? defaultIdFactory();
  const listeners = new Set<ToastListener>();
  const timers = new Map<string, TimerHandle>();
  let toasts: readonly Toast[] = [];

  const emit = (): void => {
    for (const listener of listeners) listener(toasts);
  };

  const clearTimer = (id: string): void => {
    const timer = timers.get(id);
    if (timer !== undefined) {
      options.scheduler.clearTimer(timer);
      timers.delete(id);
    }
  };

  const remove = (id: string): void => {
    clearTimer(id);
    const next = toasts.filter(toast => toast.id !== id);
    if (next.length === toasts.length) return;
    toasts = next;
    emit();
  };

  return {
    getToasts: () => toasts,
    show(input) {
      const severity = input.severity ?? 'info';
      assertPassiveSeverity(severity);
      const durationMs = Math.max(MIN_TOAST_DWELL_MS, input.durationMs ?? MIN_TOAST_DWELL_MS);
      const toast: Toast = {
        id: nextId(),
        message: input.message,
        severity,
        durationMs,
        ariaLive: 'polite',
      };
      toasts = [...toasts, toast];
      timers.set(
        toast.id,
        options.scheduler.setTimer(() => {
          timers.delete(toast.id);
          remove(toast.id);
        }, durationMs),
      );
      emit();
      return toast;
    },
    dismiss(id) {
      remove(id);
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    destroy() {
      for (const timer of timers.values()) options.scheduler.clearTimer(timer);
      timers.clear();
      toasts = [];
      listeners.clear();
    },
  };
};
