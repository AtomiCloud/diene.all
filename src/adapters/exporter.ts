import type { OtelOtlpExporter } from '../lib/schema.js';
import { durationToMilliseconds } from '../lib/schema.js';
import type { Environment } from '../lib/environment.js';
import { hasEnvironmentValue } from '../lib/environment.js';

type OtlpSignal = 'metrics' | 'traces';

interface OtlpExporterOptions {
  readonly headers?: Readonly<Record<string, string>>;
  readonly timeoutMillis?: number;
  readonly url?: string;
}

function otlpSignalUrl(endpoint: string, signal: OtlpSignal): string {
  const url = new URL(endpoint);
  const signalPath = `/v1/${signal}`;
  const basePath = url.pathname.replace(/\/$/, '');
  url.pathname = basePath.endsWith(signalPath) ? basePath : `${basePath}${signalPath}`;
  return url.toString();
}

function otlpExporterOptions(
  config: OtelOtlpExporter,
  signal: OtlpSignal,
  environment: Environment = process.env,
): OtlpExporterOptions {
  const upperSignal = signal.toUpperCase();
  const signalEndpoint = `OTEL_EXPORTER_OTLP_${upperSignal}_ENDPOINT`;
  const signalHeaders = `OTEL_EXPORTER_OTLP_${upperSignal}_HEADERS`;
  const signalTimeout = `OTEL_EXPORTER_OTLP_${upperSignal}_TIMEOUT`;
  return Object.freeze({
    ...(config.endpoint.length === 0 ||
    hasEnvironmentValue(environment, signalEndpoint) ||
    hasEnvironmentValue(environment, 'OTEL_EXPORTER_OTLP_ENDPOINT')
      ? {}
      : { url: otlpSignalUrl(config.endpoint, signal) }),
    ...(hasEnvironmentValue(environment, signalHeaders) ||
    hasEnvironmentValue(environment, 'OTEL_EXPORTER_OTLP_HEADERS')
      ? {}
      : { headers: Object.freeze({ ...config.headers }) }),
    ...(hasEnvironmentValue(environment, signalTimeout) ||
    hasEnvironmentValue(environment, 'OTEL_EXPORTER_OTLP_TIMEOUT')
      ? {}
      : { timeoutMillis: durationToMilliseconds(config.timeout) }),
  });
}

export type { OtlpExporterOptions, OtlpSignal };
export { otlpExporterOptions, otlpSignalUrl };
