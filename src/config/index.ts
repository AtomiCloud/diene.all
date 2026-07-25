import { ConfigRegistry } from '@atomicloud/diene.config';
import { authEngineConfigSchema } from '@atomicloud/diene.auth-engine';
import { otelBlockSchema } from '@atomicloud/diene.otel';
import { z } from 'zod';
import {
  appBlockSchema,
  brandingBlockSchema,
  deeplinkBlockSchema,
  errorCatalogBlockSchema,
  faroBlockSchema,
  pickerBlockSchema,
  seoBlockSchema,
  themeBlockSchema,
} from './blocks';

/**
 * Per-backend endpoints: the registration point in
 * `src/adapters/external/core.ts` keys off these names. URLs are config so
 * every landscape/CI can override them (R4/R21).
 */
const backendsBlockSchema = z.record(
  z.string().min(1),
  z
    .object({
      baseUrl: z.url(),
      platform: z.string().min(1),
      service: z.string().min(1),
      module: z.string().min(1),
    })
    .strict(),
);

/**
 * The service-composed config root (R21). Engine libs each export their own
 * block schema next to the code that reads it; this app composes the root by
 * importing those blocks — one line per engine — plus its own blocks.
 * lib/bun/config is only the merger/validator.
 */
export const configRegistry = ConfigRegistry.create()
  .register('app', appBlockSchema)
  .register('branding', brandingBlockSchema)
  .register('seo', seoBlockSchema)
  .register('theme', themeBlockSchema)
  .register('faro', faroBlockSchema)
  .register('picker', pickerBlockSchema)
  .register('deeplink', deeplinkBlockSchema)
  .register('errorCatalog', errorCatalogBlockSchema)
  .register('backends', backendsBlockSchema)
  .register('auth', authEngineConfigSchema)
  .register('otel', otelBlockSchema);

export type AppConfig = z.infer<typeof appBlockSchema>;
export type SeoConfig = z.infer<typeof seoBlockSchema>;
export type ThemeConfig = z.infer<typeof themeBlockSchema>;
type BrandingConfig = z.infer<typeof brandingBlockSchema>;
type FaroConfig = z.infer<typeof faroBlockSchema>;
type PickerConfig = z.infer<typeof pickerBlockSchema>;
type ErrorCatalogConfig = z.infer<typeof errorCatalogBlockSchema>;

/**
 * The CLIENT-SAFE subset injected into SSR (server tells client; the browser
 * never detects landscape and never sees a server secret). `faro.build.key`
 * is a build-time secret consumed only by the webpack plugin — it is excluded
 * here and never enters the payload.
 */
export interface ClientSafeConfig {
  readonly landscape: string;
  readonly app: AppConfig;
  readonly branding: BrandingConfig;
  readonly seo: SeoConfig;
  readonly theme: ThemeConfig;
  readonly faro: Omit<FaroConfig, 'build'>;
  readonly picker: PickerConfig;
  readonly errorCatalog: ErrorCatalogConfig;
  readonly backends: Readonly<Record<string, { readonly baseUrl: string }>>;
}
