import { type ConfigRecord, resolveLandscape } from '@atomicloud/diene.config';

export const WORKLOAD_LANDSCAPES = ['lapras', 'ditto', 'rotom', 'absol', 'eevee', 'plusle', 'minun'] as const;

export const SERVING_LANDSCAPE_FIXTURES = ['pichu', 'pikachu', 'raichu'] as const;

export type WorkloadLandscape = (typeof WORKLOAD_LANDSCAPES)[number];
export type ServingLandscapeFixture = (typeof SERVING_LANDSCAPE_FIXTURES)[number];
export type KnownLandscape = WorkloadLandscape | ServingLandscapeFixture;

export type LandscapeSource =
  | { readonly source: 'binding'; readonly value: string | undefined }
  | { readonly source: 'baked-constant'; readonly value: string | undefined }
  | { readonly source: 'dart-define'; readonly value: string | undefined };

const LANDSCAPE_TOKEN = /^[a-z0-9][a-z0-9-]*$/;

export class LandscapeAccessError extends Error {
  constructor(
    readonly source: LandscapeSource['source'],
    readonly value: string | undefined,
    readonly reason: 'missing' | 'invalid',
  ) {
    super(`landscape ${source} value is ${reason}`);
    this.name = 'LandscapeAccessError';
  }
}

/**
 * Read a host-supplied landscape. This deliberately performs no detection:
 * callers must provide a runtime binding, baked constant, or dart-define.
 */
export const landscape = (input: LandscapeSource): string => {
  const value = input.value?.trim();
  if (value === undefined || value === '') {
    throw new LandscapeAccessError(input.source, input.value, 'missing');
  }
  if (!LANDSCAPE_TOKEN.test(value)) {
    throw new LandscapeAccessError(input.source, input.value, 'invalid');
  }
  return value;
};

/** Feed the accessor value into config's canonical landscape tier resolver. */
export const landscapeConfigAnchor = (input: LandscapeSource, base: ConfigRecord = {}): string =>
  resolveLandscape(landscape(input), base);
