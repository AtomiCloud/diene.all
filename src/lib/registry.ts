import { z } from 'zod';

/** A map of config-block key → its zod schema. */
export type BlockShape = Record<string, z.ZodType>;

export class ConfigRegistryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ConfigRegistryError';
  }
}

/**
 * Immutable registry of named config blocks and their zod schemas.
 *
 * Engine libs (auth-engine, otel, …) each own and export their own block schema;
 * a service composes a registry by registering the blocks it imports plus its
 * own keys. The registry is this lib's single source for the service-composed
 * root schema — it never defines engine block schemas itself.
 *
 * `register` returns a NEW registry with the key's type threaded into the
 * accumulated shape, so the loaded config is fully typed per block.
 */
export class ConfigRegistry<S extends BlockShape = BlockShape> {
  private constructor(private readonly shape: S) {}

  /** Start an empty registry. */
  static create(): ConfigRegistry<Record<string, never>> {
    return new ConfigRegistry<Record<string, never>>({});
  }

  /** Register a block; throws if the key is already registered. */
  register<K extends string, T extends z.ZodType>(key: K, schema: T): ConfigRegistry<S & Record<K, T>> {
    if (Object.hasOwn(this.shape, key)) {
      throw new ConfigRegistryError(`config block "${key}" is already registered`);
    }
    return new ConfigRegistry<S & Record<K, T>>({ ...this.shape, [key]: schema } as S & Record<K, T>);
  }

  /** The registered block keys. */
  get keys(): readonly string[] {
    return Object.keys(this.shape);
  }

  /** The composed root schema: a zod object of every registered block. */
  rootSchema(): z.ZodObject<S> {
    return z.object(this.shape);
  }
}
