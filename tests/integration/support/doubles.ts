import type { Span, SpanContext, Tracer } from '@opentelemetry/api';
import type { Logger } from 'pino';

// White-box integration doubles. Every SDK-touching seam is exercised in
// process with injected fakes so no collector, container, network client, or
// background timer is ever created. Fakes record their interactions so tests
// can assert the adapter's behaviour by capture rather than by side effect.

// A frozen, well-formed span context for the trace-correlation branch.
const VALID_SPAN_CONTEXT: SpanContext = {
  traceId: '0af7651916cd43dd8448eb211c80319c',
  spanId: 'b7ad6b7169203331',
  traceFlags: 1,
};

interface SpanControls {
  readonly endThrows?: boolean;
}

interface RecordedSpan {
  readonly events: { name: string; attributes?: unknown }[];
  readonly statuses: unknown[];
  ends: number;
}

function makeSpan(controls: SpanControls = {}): { span: Span; recorded: RecordedSpan } {
  const recorded: RecordedSpan = { events: [], statuses: [], ends: 0 };
  const span = {
    addEvent(name: string, attributes?: unknown) {
      recorded.events.push({ name, attributes });
      return span;
    },
    setStatus(status: unknown) {
      recorded.statuses.push(status);
      return span;
    },
    end() {
      recorded.ends += 1;
      if (controls.endThrows) throw new Error('span end failed');
    },
  } as unknown as Span;
  return { span, recorded };
}

interface TracerControls {
  readonly startThrows?: boolean;
  readonly span?: { span: Span; recorded: RecordedSpan };
}

function makeTracer(controls: TracerControls = {}): { tracer: Tracer; started: string[]; span?: RecordedSpan } {
  const started: string[] = [];
  const held = controls.span;
  const tracer = {
    startSpan(name: string) {
      started.push(name);
      if (controls.startThrows) throw new Error('startSpan failed');
      return (held ?? makeSpan()).span;
    },
  } as unknown as Tracer;
  return { tracer, started, span: held?.recorded };
}

interface LoggerControls {
  readonly emitThrows?: boolean;
  readonly flushThrows?: boolean;
}

function makeLogger(controls: LoggerControls = {}): { logger: Logger; levels: string[]; flushes: number } {
  const levels: string[] = [];
  const state = { flushes: 0 };
  const logger = {
    trace() {
      throw new Error('unused');
    },
    info() {
      levels.push('info');
      if (controls.emitThrows) throw new Error('emit failed');
    },
    flush() {
      state.flushes += 1;
      if (controls.flushThrows) throw new Error('flush failed');
    },
  } as unknown as Logger;
  return {
    logger,
    levels,
    get flushes() {
      return state.flushes;
    },
  };
}

interface CaptureStream {
  readonly lines: string[];
  write(chunk: string): void;
}

function makeCaptureStream(): CaptureStream {
  const lines: string[] = [];
  return {
    lines,
    write(chunk: string) {
      for (const line of chunk.split('\n')) if (line.trim().length > 0) lines.push(line);
    },
  };
}

export type { CaptureStream, RecordedSpan };
export { makeCaptureStream, makeLogger, makeSpan, makeTracer, VALID_SPAN_CONTEXT };
