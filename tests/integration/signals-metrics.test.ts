import { describe, it } from 'bun:test';
import type { MeterProvider as MeterProviderType } from '@opentelemetry/sdk-metrics';
import { ConsoleMetricExporter, MeterProvider } from '@opentelemetry/sdk-metrics';
import { OTLPMetricExporter } from '@opentelemetry/exporter-metrics-otlp-proto';
import { resourceFromAttributes } from '@opentelemetry/resources';
import 'should';
import type { Environment } from '../../src/lib/environment';
import type { OtelMetrics } from '../../src/lib/schema';
import {
  createMetricSignal,
  defaultMetricExporterFactories,
  metricExportTimeoutMilliseconds,
  metricIntervalMilliseconds,
  SdkMetricsCollector,
} from '../../src/adapters/signals/metrics';
import { makeMetricFactories, makeThrowingMeter } from './support/factories';
import { expectErr, expectOk } from './support/result';

const resource = resourceFromAttributes({ 'service.name': 'diene' });

function metricsConfig(overrides: Partial<OtelMetrics> = {}): OtelMetrics {
  return {
    enabled: true,
    interval: 'PT60S',
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

describe('metricIntervalMilliseconds', () => {
  it.each([
    ['a positive integer override', { OTEL_METRIC_EXPORT_INTERVAL: '5000' }, 5000],
    ['a non-numeric override', { OTEL_METRIC_EXPORT_INTERVAL: 'soon' }, 60_000],
    ['a zero override', { OTEL_METRIC_EXPORT_INTERVAL: '0' }, 60_000],
    ['no override', {}, 60_000],
  ])('should resolve the interval for %s', (_label, environment, expected) => {
    // Act
    const actual = metricIntervalMilliseconds(metricsConfig(), environment as Environment);

    // Assert
    actual.should.eql(expected);
  });
});

describe('metricExportTimeoutMilliseconds', () => {
  it.each([
    ['a positive integer override', { OTEL_METRIC_EXPORT_TIMEOUT: '2500' }, 2500],
    ['no override', {}, 10_000],
  ])('should resolve the timeout for %s', (_label, environment, expected) => {
    // Act
    const actual = metricExportTimeoutMilliseconds(metricsConfig(), environment as Environment);

    // Assert
    actual.should.eql(expected);
  });
});

describe('defaultMetricExporterFactories', () => {
  it('should construct real SDK exporters without a network client', () => {
    // Act
    const consoleExporter = defaultMetricExporterFactories.console();
    const otlpExporter = defaultMetricExporterFactories.otlp({});

    // Assert
    (consoleExporter instanceof ConsoleMetricExporter).should.be.true();
    (otlpExporter instanceof OTLPMetricExporter).should.be.true();
  });
});

describe('SdkMetricsCollector', () => {
  it('should record counter, gauge and histogram metrics and cache instruments', async () => {
    // Arrange - a real MeterProvider with a capturing exporter (no collector)
    const spy = makeMetricFactories();
    const signal = createMetricSignal(
      metricsConfig(),
      { console: true, otlp: false },
      resource,
      'diene',
      '1.0.0',
      {},
      spy.factories,
    );

    // Act - two counter records share an instrument; gauge and histogram add their own
    await expectOk(signal.collector.record({ kind: 'counter', name: 'hits', value: 1 }));
    await expectOk(signal.collector.record({ kind: 'counter', name: 'hits', value: 2 }));
    await expectOk(signal.collector.record({ kind: 'gauge', name: 'queue', value: 3 }));
    await expectOk(signal.collector.record({ kind: 'histogram', name: 'latency', value: 4, unit: 'ms' }));
    await expectOk(signal.collector.flush());
    await (signal.provider as MeterProviderType).forceFlush();

    // Assert - the reader exported at least one batch through the injected exporter
    (spy.exporter.exported.length > 0).should.be.true();
    spy.consoleCalls.should.eql(1);

    // Cleanup - stops the periodic reader timer
    await (signal.provider as MeterProviderType).shutdown();
  });

  it('should build an OTLP reader when the OTLP exporter is selected', async () => {
    // Arrange
    const spy = makeMetricFactories();

    // Act
    const signal = createMetricSignal(
      metricsConfig(),
      { console: false, otlp: true },
      resource,
      'diene',
      '1',
      {},
      spy.factories,
    );

    // Assert
    signal.active.should.be.true();
    spy.otlpCalls.should.eql(1);

    // Cleanup
    await (signal.provider as MeterProviderType).shutdown();
  });

  it('should reject a malformed metric before recording', async () => {
    // Arrange
    const collector = new SdkMetricsCollector(makeThrowingMeter());

    // Act
    const error = await expectErr(collector.record({ kind: 'counter', name: '', value: 1 }));

    // Assert
    error.code.should.eql('invalid-input');
  });

  it('should surface an io error when the meter throws', async () => {
    // Arrange
    const collector = new SdkMetricsCollector(makeThrowingMeter());

    // Act
    const error = await expectErr(collector.record({ kind: 'counter', name: 'hits', value: 1 }));

    // Assert
    error.code.should.eql('io');
    error.operation.should.eql('record');
  });

  it('should build no MeterProvider when no exporter is selected', async () => {
    // Arrange - the canonical no-exporter case: signal enabled, both exporters off
    const signal = createMetricSignal(metricsConfig(), { console: false, otlp: false }, resource, 'diene', '1');

    // Assert - inactive, provider-free no-op flavour (no MeterProvider constructed)
    signal.active.should.be.false();
    (signal.provider === undefined).should.be.true();
    await expectOk(signal.collector.flush());
    await expectOk(signal.collector.record({ kind: 'counter', name: 'noop', value: 1 }));
  });

  it('should build no MeterProvider when the metrics signal is disabled', async () => {
    // Arrange - a disabled signal wires an inactive, provider-free collector
    const signal = createMetricSignal(
      metricsConfig({ enabled: false }),
      { console: false, otlp: false },
      resource,
      'diene',
      '1',
    );

    // Assert
    signal.active.should.be.false();
    (signal.provider === undefined).should.be.true();
    await expectOk(signal.collector.flush());
  });

  it('should validate but never create an instrument when inactive', async () => {
    // Arrange - an inactive collector over a meter that throws if ever touched
    const collector = new SdkMetricsCollector(makeThrowingMeter(), undefined, false);

    // Act / Assert - a valid record succeeds without creating/caching an instrument
    await expectOk(collector.record({ kind: 'counter', name: 'noop', value: 1 }));
    // Assert - validation still runs first, so a malformed record is rejected
    const error = await expectErr(collector.record({ kind: 'counter', name: '', value: 1 }));
    error.code.should.eql('invalid-input');
  });

  it('should surface an io error when the provider flush rejects', async () => {
    // Arrange
    const provider = { forceFlush: async () => Promise.reject(new Error('flush boom')) } as unknown as MeterProvider;
    const meter = new MeterProvider().getMeter('diene');
    const collector = new SdkMetricsCollector(meter, provider);

    // Act
    const error = await expectErr(collector.flush());

    // Assert
    error.operation.should.eql('flush');
  });
});
