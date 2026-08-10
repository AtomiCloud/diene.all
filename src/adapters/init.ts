import type { LoggerSink, MetricsCollector, TelemetryAttributes } from '@atomicloud/diene.interfaces';
import type { Meter, Tracer } from '@opentelemetry/api';
import type { Resource } from '@opentelemetry/resources';
import type { DestinationStream, Logger } from 'pino';
import { exporterSelection, type Environment, type ExporterSelection, isOtelSdkDisabled } from '../lib/environment.js';
import { appIdentitySchema, createOtelResource, type AppIdentity, resourceAttributes } from '../lib/resource.js';
import type { TraceEmitter } from '../lib/trace-seam.js';
import { otelBlockSchema, type OtelBlock } from '../lib/schema.js';
import { createLoggerSignal, type LoggerSignal } from './signals/logs.js';
import {
  createMetricSignal,
  inactiveMetricSignal,
  type MetricExporterFactories,
  type MetricSignal,
} from './signals/metrics.js';
import {
  createTraceSignal,
  inactiveTraceSignal,
  type TraceSignal,
  type TraceSignalFactories,
} from './signals/traces.js';

const NO_EXPORTERS: ExporterSelection = Object.freeze({ console: false, otlp: false });

interface OtelSeamOverrides {
  readonly logger?: LoggerSink;
  readonly metrics?: MetricsCollector;
  readonly traces?: TraceEmitter;
}

interface OtelInitOptions {
  readonly destination?: DestinationStream;
  /**
   * Overrides this library's environment decisions for deterministic tests.
   * SDK-native parsing still reads `process.env`; production callers should
   * omit this option (or pass `process.env`) when relying on standard OTEL_* vars.
   */
  readonly environment?: Environment;
  readonly metricExporterFactories?: MetricExporterFactories;
  readonly seams?: OtelSeamOverrides;
  readonly traceSignalFactories?: TraceSignalFactories;
}

interface OtelActiveSignals {
  readonly logs: boolean;
  readonly metrics: boolean;
  readonly traces: boolean;
}

interface OtelRuntime {
  readonly active: OtelActiveSignals;
  readonly block: OtelBlock;
  readonly identity: AppIdentity;
  readonly logger: Logger;
  readonly loggerSink: LoggerSink;
  readonly meter: Meter;
  readonly metricsCollector: MetricsCollector;
  readonly otlpLogsBridge: LoggerSignal['otlpBridge'];
  readonly resource: Resource;
  readonly resourceAttributes: TelemetryAttributes;
  readonly traceEmitter: TraceEmitter;
  readonly tracer: Tracer;
  flush(): Promise<void>;
  shutdown(): Promise<void>;
}

function selectedExporters(
  disabled: boolean,
  block: OtelBlock,
  environment: Environment,
): Readonly<{ logs: ExporterSelection; metrics: ExporterSelection; traces: ExporterSelection }> {
  if (disabled) return Object.freeze({ logs: NO_EXPORTERS, metrics: NO_EXPORTERS, traces: NO_EXPORTERS });
  return Object.freeze({
    logs: exporterSelection(block.logs.exporter, 'OTEL_LOGS_EXPORTER', environment),
    metrics: exporterSelection(block.metrics.exporter, 'OTEL_METRICS_EXPORTER', environment),
    traces: exporterSelection(block.traces.exporter, 'OTEL_TRACES_EXPORTER', environment),
  });
}

function initOtel(block: OtelBlock, identity: AppIdentity, options: OtelInitOptions = {}): OtelRuntime {
  const validatedBlock = otelBlockSchema.parse(block);
  const validatedIdentity = appIdentitySchema.parse(identity);
  const environment = options.environment ?? process.env;
  const disabled = isOtelSdkDisabled(environment);
  const selections = selectedExporters(disabled, validatedBlock, environment);
  const attributes = resourceAttributes(validatedIdentity, environment);
  const resource = createOtelResource(validatedIdentity, environment);
  const scopeName = validatedIdentity.service;
  const scopeVersion = validatedIdentity.version;

  // Reconcile injected seams BEFORE any SDK construction. An injected seam owns
  // emit/record/flush for an enabled, non-disabled signal, so its SDK pipeline
  // (exporter/reader/processor/provider/registration) must never be built and
  // the accessor becomes a provider-free no-op. Disabled signals ignore seams.
  const loggerSeam = !disabled && validatedBlock.logs.enabled ? options.seams?.logger : undefined;
  const metricSeam = !disabled && validatedBlock.metrics.enabled ? options.seams?.metrics : undefined;
  const traceSeam = !disabled && validatedBlock.traces.enabled ? options.seams?.traces : undefined;

  const loggerSignal = createLoggerSignal(
    validatedBlock.logs.enabled && !disabled && loggerSeam === undefined,
    selections.logs,
    attributes,
    options.destination,
  );
  const metricSignal: MetricSignal =
    metricSeam === undefined
      ? createMetricSignal(
          validatedBlock.metrics,
          selections.metrics,
          resource,
          scopeName,
          scopeVersion,
          environment,
          options.metricExporterFactories,
        )
      : inactiveMetricSignal();
  const traceSignal: TraceSignal =
    traceSeam === undefined
      ? createTraceSignal(
          validatedBlock.traces,
          selections.traces,
          resource,
          scopeName,
          scopeVersion,
          environment,
          options.traceSignalFactories,
        )
      : inactiveTraceSignal(scopeName, scopeVersion);

  const loggerSink = loggerSeam ?? loggerSignal.sink;
  const metricsCollector = metricSeam ?? metricSignal.collector;
  const traceEmitter = traceSeam ?? traceSignal.emitter;

  let closed = false;
  let shutdownPromise: Promise<void> | undefined;

  async function flushSignals(): Promise<void> {
    await Promise.all([loggerSink.flush().unwrap(), metricsCollector.flush().unwrap(), traceEmitter.flush().unwrap()]);
  }

  async function flush(): Promise<void> {
    if (closed) return;
    await flushSignals();
  }

  function shutdown(): Promise<void> {
    if (shutdownPromise !== undefined) return shutdownPromise;
    closed = true;
    shutdownPromise = (async () => {
      const failures: unknown[] = [];
      try {
        await flushSignals();
      } catch (error) {
        failures.push(error);
      }
      const shutdownResults = await Promise.allSettled([
        metricSignal.provider?.shutdown(),
        traceSignal.provider?.shutdown(),
      ]);
      failures.push(
        ...shutdownResults
          .filter((result): result is PromiseRejectedResult => result.status === 'rejected')
          .map(result => result.reason),
      );
      if (failures.length > 0) throw new AggregateError(failures, 'OpenTelemetry shutdown failed');
    })();
    return shutdownPromise;
  }

  return Object.freeze({
    active: Object.freeze({
      logs: loggerSignal.active,
      metrics: metricSignal.active,
      traces: traceSignal.active,
    }),
    block: validatedBlock,
    flush,
    identity: validatedIdentity,
    logger: loggerSignal.logger,
    loggerSink,
    meter: metricSignal.meter,
    metricsCollector,
    otlpLogsBridge: loggerSignal.otlpBridge,
    resource,
    resourceAttributes: attributes,
    shutdown,
    traceEmitter,
    tracer: traceSignal.tracer,
  });
}

export type { OtelActiveSignals, OtelInitOptions, OtelRuntime, OtelSeamOverrides };
export { initOtel, selectedExporters };
