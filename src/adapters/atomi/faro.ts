'use client';

import { initializeFaro, type Faro } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';
import type { ClientSafeConfig } from '@/config';
import { faroApp, faroAttrs } from '@/lib/faro-attrs';

let faro: Faro | undefined;

/**
 * Initialize Faro with the LPSM attributes from the SSR-injected config.
 * Landscape rides the payload (server tells client) so one artifact reports
 * correctly under every binding. The attribute map and app descriptor are
 * derived by the pure `src/lib/faro-attrs` extraction; this adapter only feeds
 * them to the browser SDK. Idempotent — repeated provider mounts no-op.
 */
export const initFaro = (config: ClientSafeConfig): Faro | undefined => {
  if (!config.faro.enabled || faro !== undefined) return faro;
  faro = initializeFaro({
    url: config.faro.endpoint,
    app: faroApp(config, process.env['NEXT_PUBLIC_APP_VERSION'] ?? '0.0.0'),
    sessionTracking: { enabled: true },
    instrumentations: [new TracingInstrumentation()],
  });
  faro.api.setSession({ attributes: { ...faroAttrs(config) } });
  return faro;
};

/** The live Faro instance, if initialization has run and was enabled. */
export const getFaro = (): Faro | undefined => faro;
