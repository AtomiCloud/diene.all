import { describe, it } from 'bun:test';
import 'should';
import type { Environment } from '../../src/lib/environment';
import { exporterSelection, hasEnvironmentValue, isOtelSdkDisabled } from '../../src/lib/environment';
import type { OtelExporter } from '../../src/lib/schema';

const bothOn: OtelExporter = {
  console: { enabled: true },
  otlp: { enabled: true, endpoint: 'http://c:4318', protocol: 'http/protobuf', headers: {}, timeout: 'PT10S' },
};
const bothOff: OtelExporter = {
  console: { enabled: false },
  otlp: { enabled: false, endpoint: '', protocol: 'http/protobuf', headers: {}, timeout: 'PT10S' },
};

describe('hasEnvironmentValue', () => {
  it.each([
    ['a populated value', { NAME: 'value' }, true],
    ['a whitespace value', { NAME: '   ' }, false],
    ['an empty value', { NAME: '' }, false],
    ['an absent value', {}, false],
  ])('should report %s', (_label, environment, expected) => {
    // Act
    const actual = hasEnvironmentValue(environment as Environment, 'NAME');

    // Assert
    actual.should.eql(expected);
  });
});

describe('isOtelSdkDisabled', () => {
  it.each([
    ['lowercase true', { OTEL_SDK_DISABLED: 'true' }, true],
    ['mixed case with padding', { OTEL_SDK_DISABLED: '  TRUE ' }, true],
    ['the string false', { OTEL_SDK_DISABLED: 'false' }, false],
    ['an unset flag', {}, false],
  ])('should report %s', (_label, environment, expected) => {
    // Act
    const actual = isOtelSdkDisabled(environment as Environment);

    // Assert
    actual.should.eql(expected);
  });

  it('should default to process.env when no environment is supplied', () => {
    // Arrange
    const saved = process.env.OTEL_SDK_DISABLED;
    delete process.env.OTEL_SDK_DISABLED;

    try {
      // Act
      const actual = isOtelSdkDisabled();

      // Assert
      actual.should.be.false();
    } finally {
      if (saved !== undefined) process.env.OTEL_SDK_DISABLED = saved;
    }
  });
});

describe('exporterSelection', () => {
  it('should fall back to the configured booleans when the override is absent', () => {
    // Act
    const actual = exporterSelection(bothOn, 'OTEL_TRACES_EXPORTER', {});

    // Assert
    actual.should.eql({ console: true, otlp: true });
  });

  it('should treat a blank override as absent', () => {
    // Act
    const actual = exporterSelection(bothOff, 'OTEL_METRICS_EXPORTER', { OTEL_METRICS_EXPORTER: '   ' });

    // Assert - the configured (disabled) booleans win
    actual.should.eql({ console: false, otlp: false });
  });

  it('should disable every exporter when the override lists none', () => {
    // Act
    const actual = exporterSelection(bothOn, 'OTEL_LOGS_EXPORTER', { OTEL_LOGS_EXPORTER: 'none' });

    // Assert
    actual.should.eql({ console: false, otlp: false });
  });

  it('should select exactly the exporters named in the override', () => {
    // Act
    const actual = exporterSelection(bothOff, 'OTEL_TRACES_EXPORTER', { OTEL_TRACES_EXPORTER: ' console , otlp ' });

    // Assert - the override wins over the configured off booleans
    actual.should.eql({ console: true, otlp: true });
  });

  it('should select only console when the override names console alone', () => {
    // Act
    const actual = exporterSelection(bothOn, 'OTEL_TRACES_EXPORTER', { OTEL_TRACES_EXPORTER: 'console' });

    // Assert
    actual.should.eql({ console: true, otlp: false });
  });

  it('should default to process.env when no environment is supplied', () => {
    // Arrange
    const saved = process.env.OTEL_TRACES_EXPORTER;
    delete process.env.OTEL_TRACES_EXPORTER;

    try {
      // Act
      const actual = exporterSelection(bothOn, 'OTEL_TRACES_EXPORTER');

      // Assert - no override means the configured booleans are used
      actual.should.eql({ console: true, otlp: true });
    } finally {
      if (saved !== undefined) process.env.OTEL_TRACES_EXPORTER = saved;
    }
  });
});
