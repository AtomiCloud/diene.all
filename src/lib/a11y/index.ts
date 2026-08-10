/**
 * Accessibility module — safe-area insets and reduced-motion mechanisms.
 *
 * MECHANISM ONLY: these helpers expose `env(safe-area-inset-*)` and the
 * `prefers-reduced-motion` signal. They carry ZERO token/visual opinions (no
 * colours, no spacing scale). The core is React-free and SSR-safe; the media
 * query is behind an injected port.
 */

export type SafeAreaSide = 'top' | 'right' | 'bottom' | 'left';

export const SAFE_AREA_SIDES: readonly SafeAreaSide[] = ['top', 'right', 'bottom', 'left'];

/**
 * The `env(safe-area-inset-<side>)` expression, with an optional fallback
 * (e.g. `0px`) for platforms that don't provide the inset.
 */
export const safeAreaInset = (side: SafeAreaSide, fallback?: string): string =>
  fallback === undefined ? `env(safe-area-inset-${side})` : `env(safe-area-inset-${side}, ${fallback})`;

/**
 * A record of `--<prefix>-<side>` custom properties mapped to their
 * `env(safe-area-inset-<side>)` expressions, ready to spread into inline
 * styles. Prefix defaults to `--safe-area-inset`.
 */
export const safeAreaVars = (prefix = '--safe-area-inset', fallback?: string): Record<string, string> => {
  const vars: Record<string, string> = {};
  for (const side of SAFE_AREA_SIDES) vars[`${prefix}-${side}`] = safeAreaInset(side, fallback);
  return vars;
};

/** The four safe-area insets as a CSS `padding`-shorthand value (T R B L). */
export const safeAreaPadding = (fallback?: string): string =>
  SAFE_AREA_SIDES.map(side => safeAreaInset(side, fallback)).join(' ');

/** The canonical reduced-motion media query. */
export const REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

/** Port exposing the reduced-motion preference and its change notifications. */
export interface MediaQueryPort {
  readonly matches: () => boolean;
  readonly subscribe: (listener: (matches: boolean) => void) => () => void;
}

/** Snapshot read of the reduced-motion preference. */
export const prefersReducedMotion = (port: MediaQueryPort): boolean => port.matches();

export type ReducedMotionListener = (reduced: boolean) => void;

export interface ReducedMotionController {
  readonly isReduced: () => boolean;
  readonly subscribe: (listener: ReducedMotionListener) => () => void;
  readonly destroy: () => void;
}

/**
 * Create a reduced-motion controller that tracks the media query and notifies
 * subscribers on change. {@link ReducedMotionController.destroy} releases the
 * underlying subscription.
 */
export const createReducedMotionController = (port: MediaQueryPort): ReducedMotionController => {
  const listeners = new Set<ReducedMotionListener>();
  let reduced = port.matches();

  const unsubscribe = port.subscribe(next => {
    reduced = next;
    for (const listener of listeners) listener(reduced);
  });

  return {
    isReduced: () => reduced,
    subscribe(listener) {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    destroy() {
      unsubscribe();
      listeners.clear();
    },
  };
};

/**
 * A CSS rule that all-but-eliminates animation, transition, and smooth-scroll
 * durations for the given selector (default `*`). This is the standard
 * reduced-motion neutraliser — a mechanism, not a visual opinion.
 */
export const animationDisableCss = (selector = '*'): string =>
  `${selector}{animation-duration:0.01ms !important;animation-iteration-count:1 !important;` +
  `transition-duration:0.01ms !important;scroll-behavior:auto !important;}`;
