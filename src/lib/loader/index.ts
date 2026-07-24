/**
 * Loader module — debounced visibility for CONTENT loaders only.
 *
 * A content loader is debounced (~100ms): if the content arrives before the
 * delay elapses, the spinner never shows, so fast loads don't flash. A button
 * (action) spinner is NEVER debounced — it appears the instant it starts. The
 * core is React-free and SSR-safe; timing is behind an injected scheduler port.
 */

/** Default content-loader debounce. Button spinners ignore this entirely. */
export const CONTENT_DEBOUNCE_MS = 100;

export type LoaderKind = 'content' | 'action';

/** Opaque timer handle produced by the scheduler port. */
export type TimerHandle = unknown;

export interface SchedulerPort {
  readonly setTimer: (fn: () => void, ms: number) => TimerHandle;
  readonly clearTimer: (handle: TimerHandle) => void;
}

export type LoaderListener = (visible: boolean) => void;

export interface LoaderController {
  readonly isVisible: () => boolean;
  readonly start: () => void;
  readonly stop: () => void;
  readonly subscribe: (listener: LoaderListener) => () => void;
  readonly destroy: () => void;
}

export interface LoaderControllerOptions {
  readonly kind: LoaderKind;
  readonly scheduler: SchedulerPort;
  /** Debounce for `content` loaders only; ignored for `action`. Default 100ms. */
  readonly delayMs?: number;
}

/**
 * Create a loader controller. For `content`, {@link LoaderController.start}
 * schedules visibility after the delay and {@link LoaderController.stop} cancels
 * it — so a load that completes within the delay shows nothing. For `action`,
 * visibility flips synchronously on start (the delay is forced to zero, so a
 * button spinner can never be debounced).
 */
export const createLoaderController = (options: LoaderControllerOptions): LoaderController => {
  const delay = options.kind === 'content' ? (options.delayMs ?? CONTENT_DEBOUNCE_MS) : 0;
  const listeners = new Set<LoaderListener>();
  let visible = false;
  let timer: TimerHandle | null = null;

  const cancel = (): void => {
    if (timer !== null) {
      options.scheduler.clearTimer(timer);
      timer = null;
    }
  };

  const set = (next: boolean): void => {
    if (next === visible) return;
    visible = next;
    for (const listener of listeners) listener(visible);
  };

  return {
    isVisible: () => visible,
    start() {
      cancel();
      if (delay > 0) {
        timer = options.scheduler.setTimer(() => {
          timer = null;
          set(true);
        }, delay);
      } else {
        set(true);
      }
    },
    stop() {
      cancel();
      set(false);
    },
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    destroy() {
      cancel();
      listeners.clear();
    },
  };
};
