import type { Result } from '@atomicloud/diene.result';
import { type MetricsError, portError } from './error.js';
import { checkTelemetryAttributes, type TelemetryAttributes } from './telemetry.js';
import { accepted, type Checked, rejected, resultFromChecked } from './validation.js';

type MetricKind = 'counter' | 'gauge' | 'histogram';

interface MetricRecord {
  readonly kind: MetricKind;
  readonly name: string;
  readonly value: number;
  readonly unit?: string;
  readonly attributes?: TelemetryAttributes;
}

interface MetricsCollector {
  record(metric: MetricRecord): Result<void, MetricsError>;
  flush(): Result<void, MetricsError>;
}

const METRIC_NAME = /^[A-Za-z][A-Za-z0-9_.\-/]{0,254}$/;

function invalidMetric(field: string, message: string): Checked<never, MetricsError> {
  return rejected(portError('metrics', 'invalid-input', 'record', message, { field }));
}

function checkMetricRecord(metric: MetricRecord): Checked<Readonly<MetricRecord>, MetricsError> {
  if (typeof metric !== 'object' || metric === null) {
    return invalidMetric('metric', 'Metric record must be an object');
  }
  if (metric.kind !== 'counter' && metric.kind !== 'gauge' && metric.kind !== 'histogram') {
    return invalidMetric('kind', 'Metric kind is invalid');
  }
  if (typeof metric.name !== 'string' || !METRIC_NAME.test(metric.name)) {
    return invalidMetric('name', 'Metric name must be a valid portable instrument name');
  }
  if (typeof metric.value !== 'number' || !Number.isFinite(metric.value)) {
    return invalidMetric('value', 'Metric value must be finite');
  }
  if (metric.kind === 'counter' && metric.value < 0) {
    return invalidMetric('value', 'Counter values must not be negative');
  }
  if (metric.unit !== undefined && (typeof metric.unit !== 'string' || metric.unit.trim() === '')) {
    return invalidMetric('unit', 'Metric unit must not be blank');
  }
  const attributes = checkTelemetryAttributes(metric.attributes, 'metrics', 'record');
  if (!attributes.ok) return attributes;
  return accepted(
    Object.freeze({
      ...(attributes.value === undefined ? {} : { attributes: attributes.value }),
      kind: metric.kind,
      name: metric.name,
      value: metric.value,
      ...(metric.unit === undefined ? {} : { unit: metric.unit }),
    }),
  );
}

function validateMetricRecord(metric: MetricRecord): Result<Readonly<MetricRecord>, MetricsError> {
  return resultFromChecked(checkMetricRecord(metric));
}

export type { MetricKind, MetricRecord, MetricsCollector };
export { checkMetricRecord, validateMetricRecord };
