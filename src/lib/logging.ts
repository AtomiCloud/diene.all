import type { Result } from '@atomicloud/diene.result';
import { type LoggingError, portError } from './error.js';
import { checkTelemetryAttributes, type TelemetryAttributes } from './telemetry.js';
import { accepted, type Checked, rejected, resultFromChecked } from './validation.js';

type LogLevel = 'debug' | 'error' | 'fatal' | 'info' | 'trace' | 'warn';

interface LogRecord {
  readonly level: LogLevel;
  readonly message: string;
  readonly attributes?: TelemetryAttributes;
}

interface LoggerSink {
  emit(record: LogRecord): Result<void, LoggingError>;
  flush(): Result<void, LoggingError>;
}

function checkLogRecord(record: LogRecord): Checked<Readonly<LogRecord>, LoggingError> {
  if (typeof record !== 'object' || record === null) {
    return rejected(portError('logging', 'invalid-input', 'emit', 'Log record must be an object'));
  }
  if (!['trace', 'debug', 'info', 'warn', 'error', 'fatal'].includes(record.level)) {
    return rejected(portError('logging', 'invalid-input', 'emit', 'Log level is invalid', { field: 'level' }));
  }
  if (typeof record.message !== 'string' || record.message.trim() === '') {
    return rejected(
      portError('logging', 'invalid-input', 'emit', 'Log message must not be blank', { field: 'message' }),
    );
  }
  const attributes = checkTelemetryAttributes(record.attributes, 'logging', 'emit');
  if (!attributes.ok) return attributes;
  return accepted(
    Object.freeze({
      ...(attributes.value === undefined ? {} : { attributes: attributes.value }),
      level: record.level,
      message: record.message,
    }),
  );
}

function validateLogRecord(record: LogRecord): Result<Readonly<LogRecord>, LoggingError> {
  return resultFromChecked(checkLogRecord(record));
}

export type { LoggerSink, LogLevel, LogRecord };
export { checkLogRecord, validateLogRecord };
