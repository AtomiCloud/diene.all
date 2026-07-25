import { z } from 'zod';

// App-owned config blocks. Engine-owned blocks (auth-engine, api-engine, otel)
// are imported next to the composition in ./index.ts — this file only defines
// the blocks this template itself reads (R21: every behavior config-driven).

/** Service-tree identity (LPSM). Landscape is resolved separately (server-fed). */
export const appBlockSchema = z
  .object({
    servicetree: z
      .object({
        landscape: z.string().min(1),
        platform: z.string().min(1),
        service: z.string().min(1),
        module: z.string().min(1),
      })
      .strict(),
  })
  .strict();

/** Branding is config, never hardcoded (rebrand static guard enforces). */
export const brandingBlockSchema = z
  .object({
    appName: z.string().min(1),
    shortName: z.string().min(1),
    description: z.string().min(1),
    themeColor: z.string().min(1),
    backgroundColor: z.string().min(1),
    logo: z.string().min(1),
    favicon: z.string().min(1),
    splash: z.string().min(1),
  })
  .strict();

/** SEO / share surface (OG tags, JSON-LD, twitter cards) — fully config-driven. */
export const seoBlockSchema = z
  .object({
    baseUrl: z.url(),
    titleTemplate: z.string().min(1),
    defaultTitle: z.string().min(1),
    defaultDescription: z.string().min(1),
    ogImage: z.string().min(1),
    twitterCard: z.enum(['summary', 'summary_large_image']),
    twitterSite: z.string(),
    jsonLdOrganization: z
      .object({
        name: z.string().min(1),
        url: z.url(),
        logo: z.string().min(1),
      })
      .strict(),
  })
  .strict();

/**
 * Theme block: RUNTIME CSS-variable color control. Dark mode ALWAYS ships as a
 * config flag in this block; named themes map to light/dark appearances.
 */
export const themeBlockSchema = z
  .object({
    default: z.string().min(1),
    darkMode: z.boolean(),
    themes: z.record(z.string(), z.enum(['light', 'dark'])),
    storageKey: z.string().min(1),
  })
  .strict();

/**
 * Faro observability block. `build` is the BUILD-TIME SECRET tier: the
 * source-map upload key (`ATOMI_CLIENT__FARO__BUILD__KEY`) is CI-injected right
 * before the OpenNext build, consumed by @grafana/faro-webpack-plugin, and
 * never persisted into the artifact.
 */
export const faroBlockSchema = z
  .object({
    enabled: z.boolean(),
    endpoint: z.string(),
    app: z.string(),
    build: z
      .object({
        enabled: z.boolean(),
        endpoint: z.string(),
        app: z.string(),
        stack: z.string(),
        key: z.string(),
        gzipContents: z.boolean(),
      })
      .strict(),
  })
  .strict();

/**
 * Pre-onboarding picker (Doc B, landscape selector — sign-up only). The
 * endpoint-suffix allowlist is BAKED config; the auth issuer is always baked
 * and never doc-sourced.
 */
export const pickerBlockSchema = z
  .object({
    docBUrl: z.url(),
    allowedSuffixes: z.array(z.string().min(1)).min(1),
    pingTimeoutMs: z.number().int().positive(),
  })
  .strict();

/** Deeplink well-known documents (AASA + assetlinks) — identity values are config. */
export const deeplinkBlockSchema = z
  .object({
    appleAppId: z.string().min(1),
    androidPackage: z.string().min(1),
    androidSha256Fingerprints: z.array(z.string().min(1)).min(1),
  })
  .strict();

/** Client-side error-catalog classification (recoverable vs fatal). */
export const errorCatalogBlockSchema = z
  .object({
    enabled: z.boolean(),
    edgeBaseUrl: z.string(),
    refreshSeconds: z.number().int().positive(),
  })
  .strict();
