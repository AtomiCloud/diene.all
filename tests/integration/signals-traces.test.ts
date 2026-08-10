import { describe, it } from 'bun:test';
import { SpanStatusCode } from '@opentelemetry/api';
import {
  BatchSpanProcessor,
  ConsoleSpanExporter,
  type Sampler,
  type SpanExporter,
} from '@opentelemetry/sdk-trace-base';
import { NodeTracerProvider } from '@opentelemetry/sdk-trace-node';
import { resourceFromAttributes } from '@opentelemetry/resources';
import 'should';
import type { Environment } from '../../src/lib/environment';
import type { OtelTraces } from '../../src/lib/schema';
import type { TraceRecord } from '../../src/lib/trace-seam';
import { traceError } from '../../src/lib/trace-seam';
import { createTraceSignal, defaultTraceSignalFactories, SdkTraceEmitter } from '../../src/adapters/signals/traces';
import { makeSpan, makeTracer } from './support/doubles';
import { makeTraceFactories } from './support/factories';
import { expectErr, expectOk } from './support/result';

const resource = resourceFromAttributes({ 'service.name': 'diene' });

function tracesConfig(overrides: Partial<OtelTraces> = {}): OtelTraces {
  return {
    enabled: true,
    sampler: { type: 'parentbased_traceidratio', ratio: 1 },
    exporter: {
      console: { enabled: false },
      otlp: {
        enabled: true,
        endpoint: 'http://otel-collector:4318',
        protocol: 'http/protobuf',
        headers: {},
        timeout: 'PT10S',
      },
    },
    ...overrides,
  };
}

describe('createTraceSignal', () => {
  it('should build console and OTLP processors, register, and expose an active emitter', async () => {
    // Arrange
    const { tracer, started, span } = arrangeTracer();
    const spy = makeTraceFactories(tracer);

    // Act - both exporters selected via the block
    const signal = createTraceSignal(
      tracesConfig({ exporter: bothExporters() }),
      { console: true, otlp: true },
      resource,
      'diene',
      '1.0.0',
      {},
      spy.factories,
    );

    // Assert - each exporter and processor was constructed and the provider registered
    signal.active.should.be.true();
    spy.consoleCalls.should.eql(1);
    spy.otlpCalls.should.eql(1);
    spy.processorCalls.should.eql(2);
    spy.providerCalls.should.eql(1);
    spy.registerCalls.should.eql(1);
    spy.provider.registered.should.be.true();

    // Act - emit a record through the SDK-backed emitter
    await expectOk(signal.emitter.emit({ name: 'work' }));

    // Assert
    started.should.eql(['work']);
    span.ends.should.eql(1);
  });

  it('should construct no provider, sampler or registration when no processor is selected', () => {
    // Arrange
    const { tracer } = arrangeTracer();
    const spy = makeTraceFactories(tracer);

    // Act - the canonical off-by-default case: both exporters unselected
    const signal = createTraceSignal(
      tracesConfig(),
      { console: false, otlp: false },
      resource,
      'diene',
      '1',
      {},
      spy.factories,
    );

    // Assert - no provider factory call, no registration; a provider-free no-op tracer
    signal.active.should.be.false();
    (signal.provider === undefined).should.be.true();
    spy.processorCalls.should.eql(0);
    spy.providerCalls.should.eql(0);
    spy.registerCalls.should.eql(0);
  });

  it('should omit the programmatic sampler when OTEL_TRACES_SAMPLER is set', () => {
    // Arrange
    const { tracer } = arrangeTracer();
    const spy = makeTraceFactories(tracer);
    const environment: Environment = { OTEL_TRACES_SAMPLER: 'always_on' };

    // Act - a captured provider lets us observe the omitted sampler
    let captured: Sampler | undefined;
    const signal = createTraceSignal(
      tracesConfig(),
      { console: true, otlp: false },
      resource,
      'diene',
      '1',
      environment,
      {
        ...spy.factories,
        provider: options => {
          captured = options.sampler;
          return spy.provider;
        },
      },
    );

    // Assert
    signal.active.should.be.true();
    (captured === undefined).should.be.true();
  });
});

describe('defaultTraceSignalFactories', () => {
  it('should construct real SDK spans, processors and a provider without a network client', async () => {
    // Act - drive every default factory directly so their bodies are covered
    const consoleExporter = defaultTraceSignalFactories.console();
    const otlpExporter = defaultTraceSignalFactories.otlp({});
    const processor = defaultTraceSignalFactories.processor(otlpExporter as SpanExporter);
    const provider = defaultTraceSignalFactories.provider({ resource, spanProcessors: [processor] });
    defaultTraceSignalFactories.register(provider);

    // Assert - real SDK types, but no spans emitted so shutdown never exports
    (consoleExporter instanceof ConsoleSpanExporter).should.be.true();
    (processor instanceof BatchSpanProcessor).should.be.true();
    (provider instanceof NodeTracerProvider).should.be.true();

    // Cleanup - clears the BatchSpanProcessor timer; no collector is contacted
    await provider.shutdown();
  });
});

describe('SdkTraceEmitter', () => {
  it('should map a fully populated record onto span events and status', async () => {
    // Arrange
    const held = makeSpan();
    const { tracer } = makeTracer({ span: held });
    const subject = new SdkTraceEmitter(tracer);
    const record: TraceRecord = {
      name: 'http.request',
      attributes: { 'http.method': 'GET' },
      events: [{ name: 'sent', attributes: { bytes: 4 } }],
      status: 'ok',
      statusMessage: 'done',
    };

    // Act
    await expectOk(subject.emit(record));

    // Assert
    held.recorded.events.should.eql([{ name: 'sent', attributes: { bytes: 4 } }]);
    held.recorded.statuses.should.eql([{ code: SpanStatusCode.OK, message: 'done' }]);
    held.recorded.ends.should.eql(1);
  });

  it.each([
    ['error', SpanStatusCode.ERROR],
    ['ok', SpanStatusCode.OK],
    ['unset', SpanStatusCode.UNSET],
  ])('should map the %s status without a message', async (status, code) => {
    // Arrange
    const held = makeSpan();
    const { tracer } = makeTracer({ span: held });
    const subject = new SdkTraceEmitter(tracer);

    // Act
    await expectOk(subject.emit({ name: 's', status: status as TraceRecord['status'] }));

    // Assert
    held.recorded.statuses.should.eql([{ code }]);
  });

  it('should reject a malformed record before touching the tracer', async () => {
    // Arrange
    const { tracer, started } = makeTracer();
    const subject = new SdkTraceEmitter(tracer);

    // Act
    const error = await expectErr(subject.emit({ name: '' } as TraceRecord));

    // Assert
    error.code.should.eql('invalid-input');
    started.should.eql([]);
  });

  it('should no-op emit when inactive', async () => {
    // Arrange
    const { tracer, started } = makeTracer();
    const subject = new SdkTraceEmitter(tracer, undefined, false);

    // Act
    await expectOk(subject.emit({ name: 's' }));

    // Assert - a valid record is accepted but no span is started
    started.should.eql([]);
  });

  it('should surface an io error when the tracer throws on start', async () => {
    // Arrange
    const { tracer } = makeTracer({ startThrows: true });
    const subject = new SdkTraceEmitter(tracer);

    // Act
    const error = await expectErr(subject.emit({ name: 's' }));

    // Assert
    error.code.should.eql('io');
    error.operation.should.eql('emit');
  });

  it('should surface an io error and best-effort re-end when span.end throws', async () => {
    // Arrange - a span whose end() always throws exercises the catch and finally cleanup
    const held = makeSpan({ endThrows: true });
    const { tracer } = makeTracer({ span: held });
    const subject = new SdkTraceEmitter(tracer);

    // Act
    const error = await expectErr(subject.emit({ name: 's' }));

    // Assert - end was attempted in the try and again in the finally
    error.code.should.eql('io');
    held.recorded.ends.should.eql(2);
  });

  it('should flush through the provider', async () => {
    // Arrange
    const { tracer } = makeTracer();
    const spy = makeTraceFactories(tracer);
    const subject = new SdkTraceEmitter(tracer, spy.provider);

    // Act
    await expectOk(subject.flush());

    // Assert
    spy.provider.forceFlushCalls.should.eql(1);
  });

  it('should flush cleanly with no provider', async () => {
    // Arrange
    const { tracer } = makeTracer();
    const subject = new SdkTraceEmitter(tracer);

    // Act / Assert
    await expectOk(subject.flush());
  });

  it('should surface an io error when the provider flush rejects', async () => {
    // Arrange
    const { tracer } = makeTracer();
    const spy = makeTraceFactories(tracer, { flush: true });
    const subject = new SdkTraceEmitter(tracer, spy.provider);

    // Act
    const error = await expectErr(subject.flush());

    // Assert
    error.operation.should.eql('flush');
    // Sanity: the error factory the adapter uses is the shared trace error
    (traceError('io', 'flush', 'x') instanceof Error).should.be.true();
  });
});

function bothExporters(): OtelTraces['exporter'] {
  return {
    console: { enabled: true },
    otlp: {
      enabled: true,
      endpoint: 'http://otel-collector:4318',
      protocol: 'http/protobuf',
      headers: {},
      timeout: 'PT10S',
    },
  };
}

function arrangeTracer(): {
  tracer: ReturnType<typeof makeTracer>['tracer'];
  started: string[];
  span: { events: unknown[]; statuses: unknown[]; ends: number };
} {
  const held = makeSpan();
  const made = makeTracer({ span: held });
  return { tracer: made.tracer, started: made.started, span: held.recorded };
}
