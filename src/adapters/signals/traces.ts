import { Err, Ok, Res, type Result } from '@atomicloud/diene.result';
import { ProxyTracerProvider, SpanStatusCode, type Tracer } from '@opentelemetry/api';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto';
import type { Resource } from '@opentelemetry/resources';
import {
  BatchSpanProcessor,
  ConsoleSpanExporter,
  type Sampler,
  type SpanExporter,
  type SpanProcessor,
} from '@opentelemetry/sdk-trace-base';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import type { Environment, ExporterSelection } from '../../lib/environment.js';
import { createTraceSampler } from '../../lib/sampler.js';
import {
  checkTraceRecord,
  type TraceEmitter,
  type TraceError,
  type TraceRecord,
  traceError,
} from '../../lib/trace-seam.js';
import type { OtelTraces } from '../../lib/schema.js';
import { otlpExporterOptions, type OtlpExporterOptions } from '../exporter.js';

interface TraceProvider {
  getTracer(name: string, version?: string): Tracer;
  forceFlush(): Promise<void>;
  shutdown(): Promise<void>;
  register?(): void;
}

interface TraceProviderOptions {
  readonly resource: Resource;
  readonly sampler?: Sampler;
  readonly spanProcessors: readonly SpanProcessor[];
}

interface TraceSignalFactories {
  readonly console: () => SpanExporter;
  readonly otlp: (options: OtlpExporterOptions) => SpanExporter;
  readonly processor: (exporter: SpanExporter) => SpanProcessor;
  readonly provider: (options: TraceProviderOptions) => TraceProvider;
  readonly register: (provider: TraceProvider) => void;
}

interface TraceSignal {
  readonly active: boolean;
  readonly emitter: TraceEmitter;
  readonly provider?: TraceProvider;
  readonly tracer: Tracer;
}

const defaultTraceSignalFactories: TraceSignalFactories = Object.freeze({
  console: () => new ConsoleSpanExporter(),
  otlp: (options: OtlpExporterOptions) => new OTLPTraceExporter(options),
  processor: (exporter: SpanExporter) => new BatchSpanProcessor(exporter),
  provider: (options: TraceProviderOptions) =>
    new NodeTracerProvider({
      resource: options.resource,
      ...(options.sampler === undefined ? {} : { sampler: options.sampler }),
      spanProcessors: [...options.spanProcessors],
    }),
  register: (provider: TraceProvider) => provider.register?.(),
});

class SdkTraceEmitter implements TraceEmitter {
  constructor(
    private readonly tracer: Tracer,
    private readonly provider?: TraceProvider,
    private readonly active = true,
  ) {}

  emit(record: TraceRecord): Result<void, TraceError> {
    const checked = checkTraceRecord(record);
    if (!checked.ok) return Err(checked.error);
    if (!this.active) return Ok(undefined);

    let span: ReturnType<Tracer['startSpan']> | undefined;
    let ended = false;
    try {
      const valid = checked.value;
      span = this.tracer.startSpan(valid.name, { attributes: valid.attributes });
      for (const event of valid.events ?? []) span.addEvent(event.name, event.attributes);
      if (valid.status !== undefined || valid.statusMessage !== undefined) {
        span.setStatus({
          code:
            valid.status === 'error'
              ? SpanStatusCode.ERROR
              : valid.status === 'ok'
                ? SpanStatusCode.OK
                : SpanStatusCode.UNSET,
          ...(valid.statusMessage === undefined ? {} : { message: valid.statusMessage }),
        });
      }
      span.end();
      ended = true;
      return Ok(undefined);
    } catch (cause) {
      return Err(
        traceError('io', 'emit', 'OpenTelemetry failed to emit the trace record', {
          cause: cause instanceof Error ? cause.message : String(cause),
        }),
      );
    } finally {
      if (span !== undefined && !ended) {
        try {
          span.end();
        } catch {
          // Preserve the first SDK failure; best-effort cleanup must not replace it.
        }
      }
    }
  }

  flush(): Result<void, TraceError> {
    return Res.fromSerial<void, TraceError>(
      (async () => {
        try {
          await this.provider?.forceFlush();
          return ['ok', undefined];
        } catch (cause) {
          return [
            'err',
            traceError('io', 'flush', 'OpenTelemetry failed to flush traces', {
              cause: cause instanceof Error ? cause.message : String(cause),
            }),
          ];
        }
      })(),
    );
  }
}

// A provider-free inactive trace signal. A fresh, delegate-less
// ProxyTracerProvider yields a guaranteed local no-op tracer that never
// consults any globally registered provider. Used when no processor is selected
// (disabled signal, both exporters off, OTEL_SDK_DISABLED) or when an injected
// seam owns emit/flush, so no provider, sampler, or registration is created.
function inactiveTraceSignal(scopeName: string, scopeVersion: string): TraceSignal {
  const tracer = new ProxyTracerProvider().getTracer(scopeName, scopeVersion);
  return Object.freeze({
    active: false,
    emitter: new SdkTraceEmitter(tracer, undefined, false),
    tracer,
  });
}

function createTraceSignal(
  config: OtelTraces,
  selection: ExporterSelection,
  resource: Resource,
  scopeName: string,
  scopeVersion: string,
  environment: Environment = process.env,
  factories: TraceSignalFactories = defaultTraceSignalFactories,
): TraceSignal {
  const processors: SpanProcessor[] = [];
  if (config.enabled && selection.console) processors.push(factories.processor(factories.console()));
  if (config.enabled && selection.otlp) {
    processors.push(
      factories.processor(factories.otlp(otlpExporterOptions(config.exporter.otlp, 'traces', environment))),
    );
  }
  if (processors.length === 0) return inactiveTraceSignal(scopeName, scopeVersion);
  const sampler = createTraceSampler(config.sampler, environment);
  const provider = factories.provider({
    resource,
    ...(sampler === undefined ? {} : { sampler }),
    spanProcessors: processors,
  });
  factories.register(provider);
  const tracer = provider.getTracer(scopeName, scopeVersion);
  return Object.freeze({
    active: true,
    emitter: new SdkTraceEmitter(tracer, provider, true),
    provider,
    tracer,
  });
}

export type { TraceProvider, TraceProviderOptions, TraceSignal, TraceSignalFactories };
export { createTraceSignal, defaultTraceSignalFactories, inactiveTraceSignal, SdkTraceEmitter };
