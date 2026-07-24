import type { OtelExporter } from './schema.js';

type ExporterSelection = Readonly<{ console: boolean; otlp: boolean }>;
type Environment = Readonly<Record<string, string | undefined>>;

function hasEnvironmentValue(environment: Environment, name: string): boolean {
  const value = environment[name];
  return value !== undefined && value.trim() !== '';
}

function isOtelSdkDisabled(environment: Environment = process.env): boolean {
  return environment.OTEL_SDK_DISABLED?.trim().toLowerCase() === 'true';
}

function exporterSelection(
  configured: OtelExporter,
  environmentName: 'OTEL_LOGS_EXPORTER' | 'OTEL_METRICS_EXPORTER' | 'OTEL_TRACES_EXPORTER',
  environment: Environment = process.env,
): ExporterSelection {
  const override = environment[environmentName];
  if (override === undefined || override.trim() === '') {
    return Object.freeze({ console: configured.console.enabled, otlp: configured.otlp.enabled });
  }
  const exporters = new Set(override.split(',').map(value => value.trim().toLowerCase()));
  if (exporters.has('none')) return Object.freeze({ console: false, otlp: false });
  return Object.freeze({ console: exporters.has('console'), otlp: exporters.has('otlp') });
}

export type { Environment, ExporterSelection };
export { exporterSelection, hasEnvironmentValue, isOtelSdkDisabled };
