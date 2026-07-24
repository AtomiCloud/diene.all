import {
  checkLogRecord,
  type LoggerSink,
  type LoggingError,
  type LogRecord,
  portError,
  type TelemetryAttributes,
} from '@atomicloud/diene.interfaces';
import { Err, Ok, type Result } from '@atomicloud/diene.result';
import { context, isSpanContextValid, trace, type SpanContext } from '@opentelemetry/api';
import pino, { type DestinationStream, type Logger } from 'pino';
import type { ExporterSelection } from '../../lib/environment.js';

const OTLP_LOGS_BRIDGE_STATUS = 'stubbed' as const;

interface LoggerSignal {
  readonly active: boolean;
  readonly logger: Logger;
  readonly sink: LoggerSink;
  readonly otlpBridge: typeof OTLP_LOGS_BRIDGE_STATUS;
}

function activeSpanContext(): SpanContext | undefined {
  return trace.getSpan(context.active())?.spanContext();
}

function traceContextFields(spanContext: SpanContext | undefined): Readonly<Record<string, number | string>> {
  if (spanContext === undefined || !isSpanContextValid(spanContext)) return Object.freeze({});
  return Object.freeze({
    span_id: spanContext.spanId,
    trace_flags: spanContext.traceFlags,
    trace_id: spanContext.traceId,
  });
}

class PinoLoggerSink implements LoggerSink {
  constructor(private readonly logger: Logger) {}

  emit(record: LogRecord): Result<void, LoggingError> {
    const checked = checkLogRecord(record);
    if (!checked.ok) return Err(checked.error);
    try {
      const valid = checked.value;
      this.logger[valid.level](valid.attributes ?? {}, valid.message);
      return Ok(undefined);
    } catch (cause) {
      return Err(
        portError('logging', 'io', 'emit', 'Pino failed to emit the log record', {
          cause: cause instanceof Error ? cause.message : String(cause),
        }),
      );
    }
  }

  flush(): Result<void, LoggingError> {
    try {
      this.logger.flush();
      return Ok(undefined);
    } catch (cause) {
      return Err(
        portError('logging', 'io', 'flush', 'Pino failed to flush', {
          cause: cause instanceof Error ? cause.message : String(cause),
        }),
      );
    }
  }
}

function createLoggerSignal(
  enabled: boolean,
  selection: ExporterSelection,
  resource: TelemetryAttributes,
  destination?: DestinationStream,
  spanContext: () => SpanContext | undefined = activeSpanContext,
): LoggerSignal {
  const active = enabled && selection.console;
  const options: pino.LoggerOptions = {
    base: { ...resource },
    enabled: active,
    level: 'trace',
    // Pino decorates the mixin result while merging a log record, so hand it a
    // mutable copy of our frozen, deterministic trace-context value.
    mixin: () => ({ ...traceContextFields(spanContext()) }),
  };
  const logger = destination === undefined ? pino(options) : pino(options, destination);
  return Object.freeze({
    active,
    logger,
    otlpBridge: OTLP_LOGS_BRIDGE_STATUS,
    sink: new PinoLoggerSink(logger),
  });
}

export type { LoggerSignal };
export { activeSpanContext, createLoggerSignal, OTLP_LOGS_BRIDGE_STATUS, PinoLoggerSink, traceContextFields };
