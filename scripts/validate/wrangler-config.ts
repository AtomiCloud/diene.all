#!/usr/bin/env bun
// Wrangler config validator + ISR binding validator: the deployment
// configuration must parse, declare every landscape env, and carry the R2
// incremental cache, DO queue, D1 tag cache, and Images bindings — and must
// NOT use KV for ISR (caveats 4-5).
import { TOML } from 'bun';

const root = new URL('../../', import.meta.url).pathname;
const config = TOML.parse(await Bun.file(`${root}wrangler.toml`).text()) as Record<string, unknown>;

const errors: string[] = [];

if (typeof config['name'] !== 'string' || config['name'] === '') errors.push('missing worker name');
if (config['main'] !== '.open-next/worker.js') errors.push('main must be the OpenNext worker entry');

const envs = (config['env'] ?? {}) as Record<string, unknown>;
for (const landscape of ['pichu', 'pikachu', 'raichu']) {
  const env = envs[landscape] as { vars?: Record<string, unknown> } | undefined;
  if (env === undefined) errors.push(`missing env.${landscape}`);
  else if (env.vars?.['ATOMI_LANDSCAPE'] !== landscape) {
    errors.push(`env.${landscape} must bind ATOMI_LANDSCAPE=${landscape}`);
  }
}

const r2 = config['r2_buckets'] as { binding?: string }[] | undefined;
if (!r2?.some(bucket => bucket.binding === 'NEXT_INC_CACHE_R2_BUCKET')) {
  errors.push('missing R2 incremental cache binding (NEXT_INC_CACHE_R2_BUCKET)');
}

const durables = (config['durable_objects'] as { bindings?: { name?: string }[] } | undefined)?.bindings;
if (!durables?.some(binding => binding.name === 'NEXT_CACHE_DO_QUEUE')) {
  errors.push('missing DO queue binding (NEXT_CACHE_DO_QUEUE)');
}

const d1 = config['d1_databases'] as { binding?: string }[] | undefined;
if (!d1?.some(database => database.binding === 'NEXT_TAG_CACHE_D1')) {
  errors.push('missing D1 tag cache binding (NEXT_TAG_CACHE_D1)');
}

if (typeof (config['images'] as { binding?: string } | undefined)?.binding !== 'string') {
  errors.push('missing Images binding');
}

if ('kv_namespaces' in config) {
  errors.push('KV must never back ISR (caveat 4) — remove kv_namespaces');
}

if (errors.length > 0) {
  for (const error of errors) console.error(`wrangler.toml: ${error}`);
  process.exit(1);
}
console.log('wrangler config + ISR bindings valid');
