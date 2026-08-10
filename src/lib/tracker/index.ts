/**
 * Tracker module (ported from argon's tracker, vendor-neutral): a tiny event
 * bus the template wires to faro events; a product can fan the same events to
 * an analytics vendor without touching call sites.
 */

export interface TrackEvent {
  readonly name: string;
  readonly attributes?: Readonly<Record<string, string>>;
}

type TrackListener = (event: TrackEvent) => void;

export interface Tracker {
  readonly track: (event: TrackEvent) => void;
  readonly subscribe: (listener: TrackListener) => () => void;
}

export const createTracker = (): Tracker => {
  const listeners = new Set<TrackListener>();
  return {
    track: event => {
      for (const listener of listeners) listener(event);
    },
    subscribe: listener => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
  };
};
