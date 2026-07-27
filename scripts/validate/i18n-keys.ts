#!/usr/bin/env bun
// i18n missing-key lint (wired into the lint gate): every locale file must
// carry the exact key set of the default locale — a missing or extra key in
// any locale is a red.
import { readdirSync } from 'node:fs';

const dir = new URL('../../messages/', import.meta.url).pathname;
const files = readdirSync(dir).filter(file => file.endsWith('.json'));
const DEFAULT_LOCALE = 'en';

const flatten = (value: unknown, prefix = ''): string[] => {
  if (typeof value !== 'object' || value === null) return [prefix];
  return Object.entries(value).flatMap(([key, child]) => flatten(child, prefix === '' ? key : `${prefix}.${key}`));
};

const keySets = new Map<string, Set<string>>();
for (const file of files) {
  const locale = file.replace(/\.json$/, '');
  const parsed: unknown = JSON.parse(await Bun.file(`${dir}${file}`).text());
  keySets.set(locale, new Set(flatten(parsed)));
}

const reference = keySets.get(DEFAULT_LOCALE);
if (reference === undefined) {
  console.error(`missing default locale file: ${DEFAULT_LOCALE}.json`);
  process.exit(1);
}

let failed = false;
for (const [locale, keys] of keySets) {
  if (locale === DEFAULT_LOCALE) continue;
  const missing = [...reference].filter(key => !keys.has(key));
  const extra = [...keys].filter(key => !reference.has(key));
  for (const key of missing) {
    console.error(`${locale}.json: missing key ${key}`);
    failed = true;
  }
  for (const key of extra) {
    console.error(`${locale}.json: extra key ${key}`);
    failed = true;
  }
}

if (failed) process.exit(1);
console.log(`i18n keys consistent across ${files.length} locales (${reference.size} keys)`);
