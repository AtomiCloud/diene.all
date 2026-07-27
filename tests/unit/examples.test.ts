import { ConfigRegistry, generateJsonSchema } from '@atomicloud/diene.config';
import { describe, expect, it } from 'bun:test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { parse as parseYaml } from 'yaml';
import { type PresetName, registerStandardConfigs } from '../../src/lib/register';

const examplesDir = join(import.meta.dir, '../../docs/standards/standard-config/examples');

const cases: { name: PresetName; file: string }[] = [
  { name: 'postgres', file: 'postgres.config.yaml' },
  { name: 'cache', file: 'cache.config.yaml' },
  { name: 'kv', file: 'kv.config.yaml' },
  { name: 'storage', file: 'storage.config.yaml' },
];

describe('shipped example YAMLs validate against their generated $schema', () => {
  for (const { name, file } of cases) {
    const text = readFileSync(join(examplesDir, file), 'utf8');
    const registry = registerStandardConfigs(ConfigRegistry.create(), { which: [name] as const });

    it(`${name}: first line is a generated $schema pointer (R14 / C0 §3)`, () => {
      const firstLine = text.split('\n', 1)[0] ?? '';
      expect(firstLine).toContain('$schema=');
    });

    it(`${name}: example content validates against the registry root schema`, () => {
      const parsed = parseYaml(text) as Record<string, unknown>;
      const result = registry.rootSchema().safeParse(parsed);
      expect(result.success).toBe(true);
    });

    it(`${name}: the generated JSON schema advertises the ${name} block`, () => {
      const schema = generateJsonSchema(registry);
      const properties = (schema as { properties?: Record<string, unknown> }).properties ?? {};
      expect(Object.keys(properties)).toContain(name);
    });
  }
});
