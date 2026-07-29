import { initOtel, type OtelRuntime } from '@atomicloud/diene.otel';
import type { MercuryConfig } from './config.ts';

export function initializeMercuryTelemetry(config: MercuryConfig): OtelRuntime {
  const app = config('app');
  return initOtel(config('otel'), {
    landscape: app.landscape,
    platform: app.platform,
    service: app.service,
    module: app.module,
    version: app.version,
  });
}
