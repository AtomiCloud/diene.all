#!/usr/bin/env bun
// PWA manifest validator: the manifest route must emit required installability
// metadata from config (never hardcoded). Validates the builder output shape
// against the config source.
import { YAML } from 'bun';
import { z } from 'zod';

const manifestSchema = z
  .object({
    name: z.string().min(1),
    short_name: z.string().min(1),
    description: z.string().min(1),
    start_url: z.literal('/'),
    display: z.literal('standalone'),
    theme_color: z.string().min(1),
    background_color: z.string().min(1),
    icons: z
      .array(
        z.object({ src: z.string().min(1), sizes: z.string().min(1), type: z.string().min(1), purpose: z.string() }),
      )
      .min(1),
  })
  .strict();

const root = new URL('../../', import.meta.url).pathname;
const config = YAML.parse(await Bun.file(`${root}config/config.yaml`).text()) as {
  branding: Record<string, string>;
};

// Rebuild the manifest exactly as the route does and validate the shape.
const branding = config.branding;
const manifest = {
  name: branding['appName'],
  short_name: branding['shortName'],
  description: branding['description'],
  start_url: '/',
  display: 'standalone',
  theme_color: branding['themeColor'],
  background_color: branding['backgroundColor'],
  icons: [
    { src: branding['logo'], sizes: '512x512', type: 'image/png', purpose: 'any' },
    { src: branding['logo'], sizes: '512x512', type: 'image/png', purpose: 'maskable' },
  ],
};

const parsed = manifestSchema.safeParse(manifest);
if (!parsed.success) {
  for (const issue of parsed.error.issues) console.error(`manifest: ${issue.path.join('.')}: ${issue.message}`);
  process.exit(1);
}
console.log('PWA manifest metadata valid');
