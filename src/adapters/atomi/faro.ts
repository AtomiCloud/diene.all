'use client';

import { initializeFaro, type Faro } from '@grafana/faro-web-sdk';
import { TracingInstrumentation } from '@grafana/faro-web-tracing';
import type { ClientSafeConfig } from '@/config';

let faro: Faro | undefined;

/**
 * Initialize Faro with the LPSM attributes from the SSR-injected config.
 * Landscape rides the payload (server tells client) so one artifact reports
 * correctly under every binding. Idempotent — repeated provider mounts no-op.
 */
export const initFaro = (config: ClientSafeConfig): Faro | undefined => {
  if (!config.faro.enabled || faro !== undefined) return faro;
  const { servicetree } = config.app;
  faro = initializeFaro({
    url: config.faro.endpoint,
    app: {
      name: config.faro.app,
      version: process.env['NEXT_PUBLIC_APP_VERSION'] ?? '0.0.0',
      environment: config.landscape,
    },
    sessionTracking: { enabled: true },
    instrumentations: [new TracingInstrumentation()],
  });
  faro.api.setSession({
    attributes: {
      landscape: config.landscape,
      platform: servicetree.platform,
      service: servicetree.service,
      module: servicetree.module,
    },
  });
  return faro;
};

/** The live Faro instance, if initialization has run and was enabled. */
export const getFaro = (): Faro | undefined => faro;
