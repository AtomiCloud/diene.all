import { activeSpanContext, traceContextFields } from '@atomicloud/diene.otel';
import { type DestinationStream, pino, destination as pinoDestination } from 'pino';

/** The logging surface injected into application adapters. */
export interface ILogger {
  info(fields: Record<string, unknown>, message: string): void;
  warn(fields: Record<string, unknown>, message: string): void;
  error(fields: Record<string, unknown>, message: string): void;
}

export interface LoggerConfig {
  /** Pino level name; anything below it is dropped. */
  readonly level?: string;
  /** Where records are written. Tests pass an in-memory sink; production writes to stdout. */
  readonly destination?: DestinationStream;
  /** Source of the ambient trace context. Injected so tests never need a live OTel SDK. */
  readonly spanContext?: typeof activeSpanContext;
}

/** Build an independent logger with no module-level mutable instance. */
export function createLogger(config: LoggerConfig = {}): ILogger {
  const {
    level = 'info',
    destination = pinoDestination({ fd: 1, sync: true }),
    spanContext = activeSpanContext,
  } = config;

  // Spread because Pino mutates mixin records while traceContextFields returns a frozen object.
  return pino({ level, mixin: () => ({ ...traceContextFields(spanContext()) }) }, destination);
}
