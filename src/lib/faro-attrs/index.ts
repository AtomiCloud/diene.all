import type { ClientSafeConfig } from '@/config';

/**
 * Faro attribute derivation. Landscape rides the SSR-injected payload (server
 * tells client), so one artifact reports correctly under every binding — and
 * every signal carries the full LPSM coordinate. Pure so the attribute contract
 * is unit-covered without loading the browser SDK.
 */

/** The LPSM session attributes attached to every Faro signal. */
export interface FaroAttrs {
  readonly landscape: string;
  readonly platform: string;
  readonly service: string;
  readonly module: string;
}

/** The Faro app descriptor: name from config, version from the build tier. */
export interface FaroApp {
  readonly name: string;
  readonly version: string;
  readonly environment: string;
}

/** The four LPSM slots, in the order the observability standard names them. */
export const FARO_ATTR_KEYS = ['landscape', 'platform', 'service', 'module'] as const;

/** Build the LPSM attribute map from the client-safe config. */
export const faroAttrs = (config: ClientSafeConfig): FaroAttrs => ({
  landscape: config.landscape,
  platform: config.app.servicetree.platform,
  service: config.app.servicetree.service,
  module: config.app.servicetree.module,
});

/** Build the Faro app descriptor; landscape is the reported environment. */
export const faroApp = (config: ClientSafeConfig, version: string): FaroApp => ({
  name: config.faro.app,
  version,
  environment: config.landscape,
});
