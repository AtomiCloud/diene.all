import type { Result } from '@atomicloud/diene.result';
import { type PortError, portError } from './error.js';
import { accepted, type Checked, rejected, resultFromChecked } from './validation.js';

type TelemetryPort = 'logging' | 'metrics';
type TelemetryAttributeValue = boolean | number | string;
type TelemetryAttributes = Readonly<Record<string, TelemetryAttributeValue>>;

function checkTelemetryAttributes<P extends TelemetryPort>(
  attributes: TelemetryAttributes | undefined,
  port: P,
  operation: string,
): Checked<TelemetryAttributes | undefined, PortError<P>> {
  if (attributes === undefined) {
    return accepted(undefined);
  }
  if (
    typeof attributes !== 'object' ||
    attributes === null ||
    Array.isArray(attributes) ||
    ![Object.prototype, null].includes(Object.getPrototypeOf(attributes))
  ) {
    return rejected(portError(port, 'invalid-input', operation, 'Telemetry attributes must be a primitive record'));
  }
  const entries = Object.entries(attributes);
  if (entries.some(([key]) => key.trim() === '' || key.includes('\0'))) {
    return rejected(
      portError(port, 'invalid-input', operation, 'Telemetry attribute names must be non-blank and NUL-free'),
    );
  }
  if (
    entries.some(([, value]) => {
      const valueType = typeof value;
      return (
        (valueType !== 'string' && valueType !== 'number' && valueType !== 'boolean') ||
        (valueType === 'number' && !Number.isFinite(value))
      );
    })
  ) {
    return rejected(
      portError(port, 'invalid-input', operation, 'Telemetry attribute values must be finite primitives'),
    );
  }
  return accepted(
    Object.freeze(Object.fromEntries(entries.sort(([left], [right]) => (left === right ? 0 : left < right ? -1 : 1)))),
  );
}

function validateTelemetryAttributes<P extends TelemetryPort>(
  attributes: TelemetryAttributes | undefined,
  port: P,
  operation: string,
): Result<TelemetryAttributes | undefined, PortError<P>> {
  return resultFromChecked(checkTelemetryAttributes(attributes, port, operation));
}

export type { TelemetryAttributes, TelemetryAttributeValue };
export { checkTelemetryAttributes, validateTelemetryAttributes };
