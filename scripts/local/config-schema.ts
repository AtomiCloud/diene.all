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
  const current = await Bun.file(path)
    .text()
    .catch(() => '');
  if (current !== rendered) {
    console.error('config/schema.json is stale — run: bun scripts/local/config-schema.ts');
    process.exit(1);
  }
  console.log('config/schema.json is current');
} else {
  await Bun.write(path, rendered);
  console.log(`wrote ${path}`);
}
