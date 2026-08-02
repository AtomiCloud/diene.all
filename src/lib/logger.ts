import { activeSpanContext, traceContextFields } from '@atomicloud/diene.otel';
import { type DestinationStream, pino, destination as pinoDestination } from 'pino';

/**
 * The logging surface the application depends on. Adapters take this port rather than a concrete
 * logger so they never reach for `console` and stay trivially fakeable in tests.
 */
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

/**
 * Build a logger. Every call returns an independent instance — there is no module-level logger to
 * mutate, so a caller can never reconfigure logging out from under another.
 */
export function createLogger(config: LoggerConfig = {}): ILogger {
  const {
    level = 'info',
    destination = pinoDestination({ fd: 1, sync: true }),
    spanContext = activeSpanContext,
  } = config;

  // The mixin runs per record, so a log emitted inside a span carries that span's ids. It is
  // spread because `traceContextFields` returns a frozen object and pino merges into what it gets.
  return pino({ level, mixin: () => ({ ...traceContextFields(spanContext()) }) }, destination);
}
