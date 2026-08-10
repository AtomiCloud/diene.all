import { YamlConfigSource, loadConfig, type Config } from '@atomicloud/diene.config';
import { landscape as landscapeAccessor } from '@atomicloud/diene.frontend-utils/landscape';
import type { ClientSafeConfig } from '@/config';
import { configRegistry } from '@/config';
import { parseBuildTimeEnv } from '@/lib/build-env';

type BlockShape = Record<string, import('zod').ZodType>;
type RegistryShape<R> = R extends import('@atomicloud/diene.config').ConfigRegistry<infer S extends BlockShape>
  ? S
  : never;
export type RootConfig = Config<RegistryShape<typeof configRegistry>>;

/**
 * Landscape is RUNTIME on both server rails and NEVER browser-detected: a
 * Cloudflare Worker env binding on OpenNext, or chart-supplied server runtime
 * config in Garden. Both surface as process env on the Node runtime; the
 * frontend-utils accessor performs no detection — it only reads what the host
 * supplies.
 */
export const serverLandscape = (): string =>
  landscapeAccessor({
    source: 'binding',
    // Build-time prerender has no runtime binding yet — the artifact bakes
    // `base` (defaults only) and the real binding takes over per request.
    value: process.env['ATOMI_LANDSCAPE'] ?? process.env['LANDSCAPE'] ?? 'base',
  });

let cached: Promise<RootConfig> | undefined;

/**
 * Load and validate the composed config tree: base YAML → landscape overlay →
 * build-time env → runtime env (one tree, four tiers). Server-only; per-process
 * memoized (config is immutable for the life of the process/isolate).
 */
export const serverConfig = (): Promise<RootConfig> => {
  cached ??= loadConfig(
    new YamlConfigSource({
      dir: `${process.cwd()}/config`,
      buildTimeEnv: parseBuildTimeEnv(process.env['BUILD_TIME_VARIABLES']),
    }),
    configRegistry,
    { prefix: 'ATOMI_', landscape: serverLandscape() },
  );
  return cached;
};

/**
 * Project the CLIENT-SAFE subset for SSR injection (server tells client).
 * Secrets never enter: auth appSecret/management, otel headers, and the faro
 * build key are all excluded structurally, not by filtering.
 */
export const clientSafeConfig = (config: RootConfig, currentLandscape: string): ClientSafeConfig => {
  const faro = config.get('faro');
  const backends = config.get('backends');
  return {
    landscape: currentLandscape,
    app: config.get('app'),
    branding: config.get('branding'),
    seo: config.get('seo'),
    theme: config.get('theme'),
    faro: { enabled: faro.enabled, endpoint: faro.endpoint, app: faro.app },
    picker: config.get('picker'),
    errorCatalog: config.get('errorCatalog'),
    backends: Object.fromEntries(Object.entries(backends).map(([key, value]) => [key, { baseUrl: value.baseUrl }])),
  };
};
