#!/usr/bin/env bun
// App-Router-on-Workers caveat 2: `export const runtime = "edge"` is FORBIDDEN
// (breaks the OpenNext adapter — Node runtime only). Static forbid over src/.
import { Glob } from 'bun';

const pattern = /export\s+const\s+runtime\s*=\s*["']edge["']/;
const root = new URL('../../', import.meta.url).pathname;
let failed = false;
for await (const file of new Glob('src/**/*.{ts,tsx}').scan(root)) {
  const content = await Bun.file(`${root}${file}`).text();
  if (pattern.test(content)) {
    console.error(`${file}: runtime = "edge" is forbidden (OpenNext requires the Node runtime)`);
    failed = true;
  }
}

if (failed) process.exit(1);
console.log('no forbidden edge runtime declarations');
