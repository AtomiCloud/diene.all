import { Err, Ok, type Result } from '@atomicloud/diene.result';
import type { z } from 'zod';
import { applyEnvOverrides } from './env.js';
import { BASE_LANDSCAPE, resolveLandscape } from './landscape.js';
import { deepMerge } from './merge.js';
import type { BlockShape, ConfigRegistry } from './registry.js';
import type { ConfigSource } from './source.js';
import { ConfigValidationError, validateConfig } from './validator.js';

/** The validated config value per registered block. */
export type ConfigData<S extends BlockShape> = { [K in keyof S]: z.infer<S[K]> };

/**
 * Typed, immutable accessor over the validated configuration. Callable as
 * `config(key)`, and equivalently `config.get(key)`; `config.all()` returns the
 * whole validated object. Config is immutable per process — there is no
 * watch/reload in v1.
 */
export interface Config<S extends BlockShape> {
  <K extends keyof S>(key: K): ConfigData<S>[K];
  get<K extends keyof S>(key: K): ConfigData<S>[K];
  all(): ConfigData<S>;
}

const createAccessor = <S extends BlockShape>(data: ConfigData<S>): Config<S> => {
  const frozen = Object.freeze({ ...data }) as ConfigData<S>;
  const accessor = (<K extends keyof S>(key: K): ConfigData<S>[K] => frozen[key]) as Config<S>;
  accessor.get = <K extends keyof S>(key: K): ConfigData<S>[K] => frozen[key];
  accessor.all = (): ConfigData<S> => frozen;
  return accessor;
};

export interface LoadOptions {
  /**
   * REQUIRED env-override prefix (e.g. `ATOMI_`). There is no baked default —
   * the app/template sets it.
   */
  prefix: string;
  /**
   * Explicit landscape from the host. Omitted → service-tree `app.landscape`
   * in the base config → `base` (defaults only).
   */
  landscape?: string;
}

export class ConfigLoaderError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigLoaderError';
  }
}

/**
 * The one config-loading engine: performs the 4-tier merge
 * (base → sparse overlay → build-time injection → runtime env LAST) and
 * validates the FINAL merged layer only, fail-fast at startup.
 */
export class ConfigLoader<S extends BlockShape> {
  constructor(
    private readonly source: ConfigSource,
    private readonly registry: ConfigRegistry<S>,
    private readonly options: LoadOptions,
  ) {
    if (options.prefix === '') {
      throw new ConfigLoaderError('ConfigLoader requires a non-empty env-override prefix');
    }
  }

  async load(): Promise<Config<S>> {
    const { prefix, landscape } = this.options;
    const base = await this.source.base();
    const resolved = resolveLandscape(landscape, base);
    const overlay = resolved === BASE_LANDSCAPE ? {} : await this.source.overlay(resolved);
    const withOverlay = deepMerge(base, overlay);
    const withBuildTime = applyEnvOverrides(withOverlay, await this.source.buildTimeEnv(), prefix);
    const merged = applyEnvOverrides(withBuildTime, await this.source.runtimeEnv(), prefix);
    const validated = validateConfig(this.registry.rootSchema(), merged) as ConfigData<S>;
    return createAccessor(validated);
  }

  /**
   * Railway-oriented variant of {@link load}: a final-layer validation failure
   * becomes `Err<ConfigValidationError>` rather than a throw, so callers can
   * compose config loading without a try/catch. IO failures (a missing base
   * file, unreadable YAML) remain exceptional and still throw.
   */
  async loadResult(): Promise<Result<Config<S>, ConfigValidationError>> {
    try {
      return Ok(await this.load());
    } catch (error) {
      if (error instanceof ConfigValidationError) return Err(error);
      throw error;
    }
  }
}

/** Convenience wrapper: `new ConfigLoader(source, registry, options).load()`. */
export const loadConfig = <S extends BlockShape>(
  source: ConfigSource,
  registry: ConfigRegistry<S>,
  options: LoadOptions,
): Promise<Config<S>> => new ConfigLoader(source, registry, options).load();
