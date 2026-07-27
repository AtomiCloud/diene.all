import type { BlockShape, ConfigRegistry } from '@atomicloud/diene.config';
import { cache } from './presets/cache';
import { kv } from './presets/kv';
import { postgres } from './presets/postgres';
import { storage } from './presets/storage';

/**
 * The infra presets this library ships, by their frozen block key. A service
 * composes its root schema by registering the ones it needs (plus engine-owned
 * blocks and its own keys) into a `lib/bun/config` registry — this lib only
 * ships schemas, it never loads/merges/validates.
 */
export const PRESETS = { postgres, cache, kv, storage } as const;

/** A standard-config preset block key. */
export type PresetName = keyof typeof PRESETS;

/** The zod schema type registered for a given preset. */
export type PresetSchema<K extends PresetName> = (typeof PRESETS)[K];

export interface RegisterOptions<W extends readonly PresetName[]> {
  /** Which presets to register, e.g. `['postgres', 'cache'] as const`. */
  which: W;
}

/**
 * Register the chosen infra presets into a config registry, threading each
 * preset's type into the accumulated shape so the loaded config stays fully
 * typed per block. Registration order follows `which`; a preset key already
 * present in the registry throws (the config lib's register invariant).
 *
 * ```ts
 * const registry = registerStandardConfigs(ConfigRegistry.create(), {
 *   which: ['postgres', 'cache'] as const,
 * });
 * ```
 */
export const registerStandardConfigs = <S extends BlockShape, W extends readonly PresetName[]>(
  registry: ConfigRegistry<S>,
  options: RegisterOptions<W>,
): ConfigRegistry<S & { [K in W[number]]: PresetSchema<K> }> => {
  let next = registry as ConfigRegistry<BlockShape>;
  for (const name of options.which) {
    next = next.register(name, PRESETS[name]);
  }
  return next as unknown as ConfigRegistry<S & { [K in W[number]]: PresetSchema<K> }>;
};
