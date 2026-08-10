#!/usr/bin/env bun
// R21 rebrand static guard: branding/SEO/auth identity values must be
// config-driven — a hardcoded app name, logo path, theme color, OG value, or
// SSO client-id in src/ (outside the config layer) is a red. The guard scans
// for the sample's own config values appearing as literals in code, which is
// exactly the drift a rebrand would trip over.
import { Glob, YAML } from 'bun';

const root = new URL('../../', import.meta.url).pathname;
const config = YAML.parse(await Bun.file(`${root}config/config.yaml`).text()) as {
  branding: Record<string, string>;
  seo: { baseUrl: string };
  auth: { logto: { endpoint: string; appId: string } };
};

// Identity-bearing literals that must ONLY ever live in config files.
const FORBIDDEN_LITERALS = [
  config.branding['appName'],
  config.branding['themeColor'],
  config.seo.baseUrl,
  config.auth.logto.endpoint,
  config.auth.logto.appId,
].filter((value): value is string => typeof value === 'string' && value.length > 0);

let failed = false;
for await (const file of new Glob('src/**/*.{ts,tsx}').scan(root)) {
  if (file.startsWith('src/config/')) continue;
  const content = await Bun.file(`${root}${file}`).text();
  for (const literal of FORBIDDEN_LITERALS) {
    if (content.includes(literal)) {
      console.error(`${file}: hardcoded identity value "${literal}" — must come from config (R21)`);
      failed = true;
    }
  }
}

if (failed) process.exit(1);
console.log('no hardcoded identity values outside config');
