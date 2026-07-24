import type { Problem } from '@atomicloud/diene.problems';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { Temporal } from '@js-temporal/polyfill';
import { z } from 'zod';
import type { AuthClock } from '../provider';

const dnsLabel = z.string().regex(/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/);
/** A single hostname label — case-insensitive, but free of dots/slashes/blanks that could rewrite the host. */
const hostLabel = z.string().regex(/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$/);
const pingPathSchema = z.string().regex(/^\/(?!\/)(?!.*[\\?#\s]).*$/);
const homeLandscapeClaimsSchema = z
  .object({
    home_landscape: z
      .string()
      .transform(value => value.trim())
      .optional(),
  })
  .passthrough();

/** The fixed cluster DNS convention; a stable convention constant, not a mutable endpoint. */
export const PING_DOMAIN_SUFFIX = 'cluster.atomi.cloud';

export const landscapeSelectorSchema = z
  .object({
    platform: dnsLabel,
    tier: dnsLabel,
    landscapes: z.array(
      z
        .object({
          name: dnsLabel,
          region: z.string().trim().min(1),
          metadata: z.record(z.string(), z.unknown()).optional(),
        })
        .strict(),
    ),
  })
  .strict();

export type LandscapeSelector = z.infer<typeof landscapeSelectorSchema>;
export type LandscapeSelectorEntry = LandscapeSelector['landscapes'][number];

export type HomeLandscapeResolution =
  | { readonly phase: 'home'; readonly landscape: string }
  | { readonly phase: 'pre-onboarding' };

export interface PingCoordinate {
  readonly platform: string;
  readonly landscape: string;
  readonly service: string;
  readonly module: string;
  readonly path?: string;
}

const pingCoordinateSchema = z
  .object({
    platform: hostLabel,
    landscape: hostLabel,
    service: hostLabel,
    module: hostLabel,
    path: pingPathSchema.optional(),
  })
  .strict();
const pingTargetSchema = pingCoordinateSchema.omit({ platform: true, landscape: true });

export interface LandscapePing {
  readonly landscape: LandscapeSelectorEntry;
  readonly url: string;
  readonly healthy: boolean;
  readonly latency: Temporal.Duration;
}

function selectorProblem(error: unknown): Problem {
  return {
    type: 'about:blank',
    title: 'Invalid landscape selector',
    status: 400,
    detail: error instanceof Error ? error.message : 'The landscape selector document is invalid.',
    data: {},
  };
}

export function checkHomeLandscape(
  claims: Readonly<Record<string, unknown>>,
): Result<HomeLandscapeResolution, Problem> {
  const parsed = homeLandscapeClaimsSchema.safeParse(claims);
  if (!parsed.success) return Err(selectorProblem(parsed.error));
  const value = parsed.data.home_landscape;
  return Ok(value === undefined || value === '' ? { phase: 'pre-onboarding' } : { phase: 'home', landscape: value });
}

export function parseLandscapeSelector(input: unknown): Result<LandscapeSelector, Problem> {
  const parsed = landscapeSelectorSchema.safeParse(input);
  return parsed.success ? Ok(parsed.data) : Err(selectorProblem(parsed.error));
}

/**
 * Derive a landscape ping URL purely from validated coordinates and the fixed
 * cluster convention. No document-carried address is ever consulted, and any
 * malformed segment is rejected before it can rewrite the host.
 */
export function deriveLandscapePingUrl(coordinate: PingCoordinate): Result<string, Problem> {
  const parsed = pingCoordinateSchema.safeParse(coordinate);
  if (!parsed.success) return Err(selectorProblem(parsed.error));
  const { module, service, platform, landscape } = parsed.data;
  const path = parsed.data.path ?? '/';
  return Ok(`https://${module}.${service}.${platform}.${landscape}.${PING_DOMAIN_SUFFIX}${path}`);
}

export function pingLandscapes(
  selector: LandscapeSelector,
  coordinate: Omit<PingCoordinate, 'landscape' | 'platform'>,
  ping: (url: string, landscape: LandscapeSelectorEntry) => boolean | Promise<boolean>,
  clock: AuthClock,
): Result<readonly LandscapePing[], Problem> {
  const parsedSelector = landscapeSelectorSchema.safeParse(selector);
  const parsedTarget = pingTargetSchema.safeParse(coordinate);
  if (!parsedSelector.success) return Err(selectorProblem(parsedSelector.error));
  if (!parsedTarget.success) return Err(selectorProblem(parsedTarget.error));

  const pings = parsedSelector.data.landscapes.map(landscape =>
    deriveLandscapePingUrl({
      ...parsedTarget.data,
      platform: parsedSelector.data.platform,
      landscape: landscape.name,
    }).andThen(url =>
      Res.async<LandscapePing, Problem>(async () => {
        try {
          const started = clock.now();
          const healthy = await ping(url, landscape);
          const latency = started.until(clock.now());
          return Ok(Object.freeze({ landscape, url, healthy, latency }));
        } catch (error: unknown) {
          return Err(selectorProblem(error));
        }
      }),
    ),
  );

  return Res.all(...pings)
    .map(results => Object.freeze(results) as readonly LandscapePing[])
    .mapErr(errors => (errors as Problem[])[0] as Problem);
}

export function pickLandscape(results: readonly LandscapePing[]): LandscapeSelectorEntry | undefined {
  return [...results]
    .filter(result => result.healthy)
    .sort((left, right) => Temporal.Duration.compare(left.latency, right.latency))[0]?.landscape;
}
