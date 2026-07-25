#!/usr/bin/env bun
// CloudflareDeploy promotion policy check: CI may only `wrangler versions
// upload` — a direct `wrangler deploy` (without --dry-run) anywhere in CI
// scripts or workflows wires a production deploy and is a policy red.
import { Glob } from 'bun';

const root = new URL('../../', import.meta.url).pathname;
const targets = ['scripts/ci/**/*.sh', '.github/workflows/**/*.yaml'];

let failed = false;
for (const pattern of targets) {
  for await (const file of new Glob(pattern).scan(root)) {
    const content = await Bun.file(`${root}${file}`).text();
    for (const [index, line] of content.split('\n').entries()) {
      if (/wrangler\s+deploy\b/.test(line) && !line.includes('--dry-run')) {
        console.error(`${file}:${index + 1}: direct wrangler deploy — CI must only upload versions`);
        failed = true;
      }
    }
  }
}

if (failed) process.exit(1);
console.log('deploy policy holds: CI uploads tagged versions only');
