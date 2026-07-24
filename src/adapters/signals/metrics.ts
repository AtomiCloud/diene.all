import {
  checkMetricRecord,
  type MetricRecord,
  type MetricsCollector,
  type MetricsError,
  portError,
} from '@atomicloud/diene.interfaces';
import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { createNoopMeter, type Counter, type Gauge, type Histogram, type Meter } from '@opentelemetry/api';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-proto';
import type { Resource } from '@opentelemetry/resources';
import {
  ConsoleMetricExporter,
  MeterProvider,
  PeriodicExportingMetricReader,
  type PushMetricExporter,
} from '@opentelemetry/sdk-metrics';
import { otlpExporterOptions, type OtlpExporterOptions } from '../exporter.js';
import type { Environment, ExporterSelection } from '../../lib/environment.js';
import type { OtelMetrics } from '../../lib/schema.js';
import { durationToMilliseconds } from '../../lib/schema.js';

interface MetricExporterFactories {
  readonly console: () => PushMetricExporter;
  readonly otlp: (options: OtlpExporterOptions) => PushMetricExporter;
}

interface MetricSignal {
  readonly active: boolean;
  readonly collector: MetricsCollector;
  readonly meter: Meter;
  readonly provider?: MeterProvider;
}

const defaultMetricExporterFactories: MetricExporterFactories = Object.freeze({
  console: () => new ConsoleMetricExporter(),
  otlp: (options: OtlpExporterOptions) => new OTLPMetricExporter(options),
});

function metricIntervalMilliseconds(config: OtelMetrics, environment: Environment = process.env): number {
  const override = environment.OTEL_METRIC_EXPORT_INTERVAL;
  if (override !== undefined && /^\d+$/.test(override) && Number(override) > 0) return Number(override);
  return durationToMilliseconds(config.interval);
}

function metricExportTimeoutMilliseconds(config: OtelMetrics, environment: Environment = process.env): number {
  const override = environment.OTEL_METRIC_EXPORT_TIMEOUT;
  if (override !== undefined && /^\d+$/.test(override) && Number(override) > 0) return Number(override);
  return durationToMilliseconds(config.exporter.otlp.timeout);
}

class SdkMetricsCollector implements MetricsCollector {
  private readonly counters = new Map<string, Counter>();
  private readonly gauges = new Map<string, Gauge>();
  private readonly histograms = new Map<string, Histogram>();

  constructor(
    private readonly meter: Meter,
    private readonly provider?: MeterProvider,
    private readonly active = true,
  ) {}

  record(metric: MetricRecord): Result<void, MetricsError> {
    const checked = checkMetricRecord(metric);
    if (!checked.ok) return Err(checked.error);
    // Inactive metrics validate but never create or cache an instrument: no
    // exporter was selected, so there is no provider to accumulate the record.
    if (!this.active) return Ok(undefined);
    const valid = checked.value;
    try {
      const key = `${valid.name}\0${valid.unit ?? ''}`;
      if (valid.kind === 'counter') {
        const instrument = this.counters.get(key) ?? this.meter.createCounter(valid.name, { unit: valid.unit });
        this.counters.set(key, instrument);
        instrument.add(valid.value, valid.attributes);
      } else if (valid.kind === 'gauge') {
        const instrument = this.gauges.get(key) ?? this.meter.createGauge(valid.name, { unit: valid.unit });
        this.gauges.set(key, instrument);
        instrument.record(valid.value, valid.attributes);
      } else {
        const instrument = this.histograms.get(key) ?? this.meter.createHistogram(valid.name, { unit: valid.unit });
        this.histograms.set(key, instrument);
        instrument.record(valid.value, valid.attributes);
      }
      return Ok(undefined);
    } catch (cause) {
      return Err(
        portError('metrics', 'io', 'record', 'OpenTelemetry failed to record the metric', {
          cause: cause instanceof Error ? cause.message : String(cause),
        }),
      );
    }
  }

  flush(): Result<void, MetricsError> {
    return Res.fromSerial<void, MetricsError>(
      (async () => {
        try {
          await this.provider?.forceFlush();
          return ['ok', undefined];
        } catch (cause) {
          return [
            'err',
            portError('metrics', 'io', 'flush', 'OpenTelemetry failed to flush metrics', {
              cause: cause instanceof Error ? cause.message : String(cause),
            }),
          ];
        }
      })(),
    );
  }
}

// A provider-free inactive metric signal: an API no-op meter plus a validating
// collector that never creates an instrument. Used when no exporter is selected
// (disabled signal, both exporters off, OTEL_SDK_DISABLED) or when an injected
// seam owns record/flush, so no MeterProvider is ever constructed.
function inactiveMetricSignal(): MetricSignal {
  const meter = createNoopMeter();
  return Object.freeze({
    active: false,
    collector: new SdkMetricsCollector(meter, undefined, false),
    meter,
  });
}

function createMetricSignal(
  config: OtelMetrics,
  selection: ExporterSelection,
  resource: Resource,
  scopeName: string,
  scopeVersion: string,
  environment: Environment = process.env,
  factories: MetricExporterFactories = defaultMetricExporterFactories,
): MetricSignal {
  const useConsole = config.enabled && selection.console;
  const useOtlp = config.enabled && selection.otlp;
  if (!useConsole && !useOtlp) return inactiveMetricSignal();
  const readers: PeriodicExportingMetricReader[] = [];
  const interval = metricIntervalMilliseconds(config, environment);
  const timeout = metricExportTimeoutMilliseconds(config, environment);
  if (useConsole) {
    readers.push(
      new PeriodicExportingMetricReader({
        exporter: factories.console(),
        exportIntervalMillis: interval,
        exportTimeoutMillis: timeout,
      }),
    );
  }
  if (useOtlp) {
    readers.push(
      new PeriodicExportingMetricReader({
        exporter: factories.otlp(otlpExporterOptions(config.exporter.otlp, 'metrics', environment)),
        exportIntervalMillis: interval,
        exportTimeoutMillis: timeout,
      }),
    );
  }
  const provider = new MeterProvider({ readers, resource });
  const meter = provider.getMeter(scopeName, scopeVersion);
  return Object.freeze({
    active: true,
    collector: new SdkMetricsCollector(meter, provider, true),
    meter,
    provider,
  });
}

export type { MetricExporterFactories, MetricSignal };
export {
  createMetricSignal,
  defaultMetricExporterFactories,
  inactiveMetricSignal,
  metricExportTimeoutMilliseconds,
  metricIntervalMilliseconds,
  SdkMetricsCollector,
};
