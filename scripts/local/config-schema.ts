#!/usr/bin/env bun
// Generate config/schema.json from the composed root registry (R14). The
// schema gen-check gate re-runs this and fails on drift, so the editor schema
// can never diverge from what the loader enforces.
import { generateJsonSchema } from '@atomicloud/diene.config';
import { configRegistry } from '../../src/config';

const schema = generateJsonSchema(configRegistry, { id: 'diene:nextjs-frontend:config' });
const path = new URL('../../config/schema.json', import.meta.url).pathname;
const rendered = `${JSON.stringify(schema, null, 2)}\n`;

if (process.argv.includes('--check')) {
  // Semantic comparison: prettier owns key ordering/whitespace of the
  // committed file, so drift is judged on the parsed value, not the bytes.
  const current = await Bun.file(path)
    .text()
    .catch(() => '');
  let parsed: unknown;
  try {
    parsed = JSON.parse(current);
  } catch {
    parsed = undefined;
  }
  if (Bun.deepEquals(parsed, JSON.parse(rendered))) {
    console.log('config/schema.json is current');
  } else {
    console.error('config/schema.json is stale — run: bun scripts/local/config-schema.ts');
    process.exit(1);
  }
} else {
  await Bun.write(path, rendered);
  console.log(`wrote ${path}`);
}
