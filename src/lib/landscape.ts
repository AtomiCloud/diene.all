import { type ConfigRecord, isRecord } from './merge.js';

/** The landscape name meaning "no overlay — base defaults only". */
export const BASE_LANDSCAPE = 'base';

const LANDSCAPE_TOKEN = /^[a-z0-9][a-z0-9-]*$/;

export class LandscapeResolutionError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'LandscapeResolutionError';
  }
}

/**
 * Decide which landscape overlay applies.
 *
 * An explicit landscape supplied by the host wins; otherwise the service-tree
 * `app.landscape` field in the base config is consulted; otherwise `base`
 * (defaults only). This lib never DETECTS the landscape itself — the host
 * (e.g. frontend-utils via `landscape()`) resolves it and passes it in.
 */
export const resolveLandscape = (explicit: string | undefined, base: ConfigRecord): string => {
  const fromBase = isRecord(base.app) && typeof base.app.landscape === 'string' ? base.app.landscape : undefined;
  const chosen = (explicit ?? fromBase ?? BASE_LANDSCAPE).trim();
  if (chosen === '' || chosen === BASE_LANDSCAPE) return BASE_LANDSCAPE;
  if (!LANDSCAPE_TOKEN.test(chosen)) {
    throw new LandscapeResolutionError(`invalid landscape name: "${chosen}"`);
  }
  return chosen;
};
