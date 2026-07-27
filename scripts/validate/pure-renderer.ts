#!/usr/bin/env bun
// Pure-renderer arch lint: pages (src/app/**/page.tsx) may import only
// translations, navigation, guards, and components — never services,
// adapters/external, or data clients. A service import in a page is a red.
import { Glob } from 'bun';

const FORBIDDEN = [
  /from\s+'@\/adapters\/external\//,
  /from\s+'@\/adapters\/problem-reporter\//,
  /from\s+'@\/adapters\/picker\//,
  /from\s+'@\/adapters\/deferred-login\//,
  /from\s+'ioredis'/,
  /from\s+'@atomicloud\/diene\.api-engine'/,
];

const root = new URL('../../', import.meta.url).pathname;
let failed = false;
for await (const file of new Glob('src/app/**/page.tsx').scan(root)) {
  const content = await Bun.file(`${root}${file}`).text();
  for (const pattern of FORBIDDEN) {
    if (pattern.test(content)) {
      console.error(`${file}: page imports a service surface (${pattern})`);
      failed = true;
    }
  }
}

if (failed) process.exit(1);
console.log('pages are pure renderers');
