import { z } from 'zod';
import type { ConfigRegistry } from './registry.js';

export interface SchemaGenOptions {
  /** Optional `$id` stamped onto the generated schema. */
  id?: string;
}

/**
 * Emit a JSON Schema for the registry's composed root schema, so every config
 * YAML's first line can point at a GENERATED `$schema` (R14). Editors then
 * validate the sample YAML against the same schema the loader enforces.
 */
export const generateJsonSchema = (
  registry: ConfigRegistry,
  options: SchemaGenOptions = {},
): Record<string, unknown> => {
  const schema = z.toJSONSchema(registry.rootSchema()) as Record<string, unknown>;
  return options.id === undefined ? schema : { $id: options.id, ...schema };
};
