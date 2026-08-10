import { describe, it } from 'bun:test';
import 'should';
import type { Environment } from '../../src/lib/environment';
import { otlpExporterOptions, otlpSignalUrl } from '../../src/adapters/exporter';
import type { OtelOtlpExporter } from '../../src/lib/schema';

const otlpConfig: OtelOtlpExporter = {
  enabled: true,
  endpoint: 'http://otel-collector:4318',
  protocol: 'http/protobuf',
  headers: { 'x-api-key': 'secret' },
  timeout: 'PT10S',
};

describe('otlpSignalUrl', () => {
  it('should append the signal path to a bare endpoint', () => {
    // Act
    const actual = otlpSignalUrl('http://otel-collector:4318', 'traces');

    // Assert
    actual.should.eql('http://otel-collector:4318/v1/traces');
  });

  it('should not double the slash on a trailing-slash endpoint', () => {
    // Act
    const actual = otlpSignalUrl('http://otel-collector:4318/', 'metrics');

    // Assert
    actual.should.eql('http://otel-collector:4318/v1/metrics');
  });

  it('should not append the signal path when the endpoint already ends with it', () => {
    // Act - an endpoint already carrying /v1/<signal> is left untouched
    const actual = otlpSignalUrl('http://otel-collector:4318/v1/traces', 'traces');

    // Assert
    actual.should.eql('http://otel-collector:4318/v1/traces');
  });
});

describe('otlpExporterOptions', () => {
  it('should derive url, headers and timeout from the block when no OTEL_* override is set', () => {
    // Act
    const actual = otlpExporterOptions(otlpConfig, 'traces', {});

    // Assert
    actual.should.eql({
      url: 'http://otel-collector:4318/v1/traces',
      headers: { 'x-api-key': 'secret' },
      timeoutMillis: 10_000,
    });
  });

  it('should omit the url when the block endpoint is empty so a standard OTEL default can win', () => {
    // Arrange - an enabled-but-endpointless block must not force a url
    const emptyEndpoint: OtelOtlpExporter = { ...otlpConfig, endpoint: '' };

    // Act
    const actual = otlpExporterOptions(emptyEndpoint, 'traces', {});

    // Assert
    ('url' in actual).should.be.false();
    ('headers' in actual).should.be.true();
    ('timeoutMillis' in actual).should.be.true();
  });

  it('should omit the url when the signal-specific endpoint env is set', () => {
    // Arrange
    const environment: Environment = { OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'http://env:4318' };

    // Act
    const actual = otlpExporterOptions(otlpConfig, 'traces', environment);

    // Assert - the SDK consumes the env var; the lib must not also set url
    ('url' in actual).should.be.false();
    ('headers' in actual).should.be.true();
    ('timeoutMillis' in actual).should.be.true();
  });

  it('should omit the url when the generic endpoint env is set', () => {
    // Arrange
    const environment: Environment = { OTEL_EXPORTER_OTLP_ENDPOINT: 'http://env:4318' };

    // Act
    const actual = otlpExporterOptions(otlpConfig, 'metrics', environment);

    // Assert
    ('url' in actual).should.be.false();
  });

  it('should omit the headers when a headers env override is present', () => {
    // Arrange
    const environment: Environment = { OTEL_EXPORTER_OTLP_METRICS_HEADERS: 'a=b' };

    // Act
    const actual = otlpExporterOptions(otlpConfig, 'metrics', environment);

    // Assert
    ('headers' in actual).should.be.false();
  });

  it('should omit the timeout when a timeout env override is present', () => {
    // Arrange
    const environment: Environment = { OTEL_EXPORTER_OTLP_TIMEOUT: '5000' };

    // Act
    const actual = otlpExporterOptions(otlpConfig, 'traces', environment);

    // Assert
    ('timeoutMillis' in actual).should.be.false();
  });

  it('should default to process.env when no environment is supplied', () => {
    // Arrange - isolate the OTLP env keys this function reads
    const keys = [
      'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT',
      'OTEL_EXPORTER_OTLP_ENDPOINT',
      'OTEL_EXPORTER_OTLP_TRACES_HEADERS',
      'OTEL_EXPORTER_OTLP_HEADERS',
      'OTEL_EXPORTER_OTLP_TRACES_TIMEOUT',
      'OTEL_EXPORTER_OTLP_TIMEOUT',
    ];
    const saved = new Map(keys.map(key => [key, process.env[key]]));
    for (const key of keys) delete process.env[key];

    try {
      // Act
      const actual = otlpExporterOptions(otlpConfig, 'traces');

      // Assert
      actual.should.containEql({ url: 'http://otel-collector:4318/v1/traces' });
    } finally {
      for (const [key, value] of saved) if (value !== undefined) process.env[key] = value;
    }
  });
});
