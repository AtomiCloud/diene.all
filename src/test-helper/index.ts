import { type Config, loadConfig } from '../lib/loader.js';
import { type ConfigRecord, isRecord } from '../lib/merge.js';
import type { BlockShape, ConfigRegistry } from '../lib/registry.js';
import type { ConfigSource, EnvRecord } from '../lib/source.js';
import { ConfigValidationError } from '../lib/validator.js';

/** Plain-object tier providers — no files, no `process.env` mutation. */
export interface InMemoryTiers {
  /** Tier 1 — base full-defaults object. */
  base?: ConfigRecord;
  /** Tier 2 — sparse landscape overlays keyed by landscape name. */
  overlays?: Record<string, ConfigRecord>;
  /** Tier 3 — build-time injected env. */
  buildTimeEnv?: EnvRecord;
  /** Tier 4 — runtime env. */
  runtimeEnv?: EnvRecord;
}

export class TestHelperError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'TestHelperError';
  }
}

/**
 * An in-memory `ConfigSource` built from plain objects. Feeds the REAL loader,
 * so a behavioral suite can run identically against files (`YamlConfigSource`)
 * and against fakes (contract parity).
 */
export class InMemoryConfigSource implements ConfigSource {
  constructor(private readonly tiers: InMemoryTiers = {}) {}

  async base(): Promise<ConfigRecord> {
    return this.tiers.base ?? {};
  }

  async overlay(landscape: string): Promise<ConfigRecord> {
    return this.tiers.overlays?.[landscape] ?? {};
  }

  async buildTimeEnv(): Promise<EnvRecord> {
    return this.tiers.buildTimeEnv ?? {};
  }

  async runtimeEnv(): Promise<EnvRecord> {
    return this.tiers.runtimeEnv ?? {};
  }
}

const DEFAULT_PREFIX = 'ATOMI_';

export interface StubOptions {
  prefix?: string;
  landscape?: string;
}

/**
 * Build a validated, typed config from in-memory tiers and a registry using the
 * REAL loader — so a stub always satisfies the zod registry (builder invariant).
 */
export const stubConfig = <S extends BlockShape>(
  registry: ConfigRegistry<S>,
  tiers: InMemoryTiers,
  options: StubOptions = {},
): Promise<Config<S>> =>
  loadConfig(new InMemoryConfigSource(tiers), registry, {
    prefix: options.prefix ?? DEFAULT_PREFIX,
    landscape: options.landscape,
  });

/**
 * Landscape-resolution fake: an in-memory source whose base carries a
 * service-tree `app.landscape`, so `resolveLandscape` selects it with no
 * explicit landscape passed.
 */
export const withLandscape = (landscape: string, tiers: InMemoryTiers = {}): InMemoryConfigSource => {
  const existingApp = isRecord(tiers.base?.app) ? tiers.base.app : {};
  return new InMemoryConfigSource({
    ...tiers,
    base: { ...(tiers.base ?? {}), app: { ...existingApp, landscape } },
  });
};

/**
 * Assertion helper: the tiers MUST produce a valid config; returns it. Throws
 * `TestHelperError` if loading rejects the final layer.
 */
export const expectValid = async <S extends BlockShape>(
  registry: ConfigRegistry<S>,
  tiers: InMemoryTiers,
  options: StubOptions = {},
): Promise<Config<S>> => {
  try {
    return await stubConfig(registry, tiers, options);
  } catch (error) {
    const detail = error instanceof ConfigValidationError ? error.issues.join('; ') : String(error);
    throw new TestHelperError(`expected a valid config, but validation failed: ${detail}`);
  }
};

/**
 * Assertion helper: the tiers MUST fail final-layer validation; returns the
 * `ConfigValidationError`. Throws `TestHelperError` if the config unexpectedly
 * validated.
 */
export const expectInvalid = async <S extends BlockShape>(
  registry: ConfigRegistry<S>,
  tiers: InMemoryTiers,
  options: StubOptions = {},
): Promise<ConfigValidationError> => {
  try {
    await stubConfig(registry, tiers, options);
  } catch (error) {
    if (error instanceof ConfigValidationError) return error;
    throw new TestHelperError(`expected a ConfigValidationError, but got: ${String(error)}`);
  }
  throw new TestHelperError('expected config validation to fail, but it succeeded');
};
