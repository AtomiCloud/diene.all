import type { IKeyValueStore, IProgressReporter, IShell } from '../../src/lib/kv/interfaces';
import type { ICliIo } from '../../src/adapters/terminal/console-io';
import type { IPrompt } from '../../src/adapters/terminal/prompt';
import type { ISpinner } from '../../src/adapters/terminal/spinner';

/** Records a single `set` call so tests can assert the composed key, value, and ttl. */
export interface SetCall {
  readonly key: string;
  readonly value: string;
  readonly ttlSeconds: number | undefined;
}

/** In-memory `IKeyValueStore` for unit tests — no real Redis; optionally throws to exercise the unreachable-backend path. */
export class FakeKeyValueStore implements IKeyValueStore {
  readonly setCalls: SetCall[] = [];
  readonly getCalls: string[] = [];
  closed = false;

  constructor(
    private readonly initial: Record<string, string> = {},
    private readonly failure?: Error,
  ) {}

  async set(key: string, value: string, ttlSeconds?: number): Promise<void> {
    if (this.failure) throw this.failure;
    this.setCalls.push({ key, value, ttlSeconds });
    this.initial[key] = value;
  }

  async get(key: string): Promise<string | null> {
    this.getCalls.push(key);
    if (this.failure) throw this.failure;
    const value = this.initial[key];
    return value === undefined ? null : value;
  }

  async close(): Promise<void> {
    this.closed = true;
  }
}

/** Captures everything written to the CLI IO so tests can assert on rendered output. */
export interface CapturedIo extends ICliIo {
  readonly successes: string[];
  readonly warnings: string[];
  readonly errors: string[];
  readonly exitCodes: number[];
}

export function captureIo(): CapturedIo {
  const successes: string[] = [];
  const warnings: string[] = [];
  const errors: string[] = [];
  const exitCodes: number[] = [];
  return {
    successes,
    warnings,
    errors,
    exitCodes,
    success: (message: string): void => {
      successes.push(message);
    },
    warn: (message: string): void => {
      warnings.push(message);
    },
    error: (message: string): void => {
      errors.push(message);
    },
    setExitCode: (code: number): void => {
      exitCodes.push(code);
    },
    interactive: (): boolean => false,
  };
}

/** Records spinner transitions so tests can assert on live feedback. */
export interface CapturedSpinner extends ISpinner {
  readonly events: string[];
}

export function captureSpinner(): CapturedSpinner {
  const events: string[] = [];
  return {
    events,
    start: (text: string): void => {
      events.push(`start:${text}`);
    },
    succeed: (text: string): void => {
      events.push(`succeed:${text}`);
    },
    fail: (text: string): void => {
      events.push(`fail:${text}`);
    },
  };
}

/** Records progress-reporter activity so tests can assert totals and ticks. */
export interface CapturedProgress extends IProgressReporter {
  readonly totals: number[];
  ticks: number;
  stopped: boolean;
}

export function captureProgress(): CapturedProgress {
  const reporter: CapturedProgress = {
    totals: [],
    ticks: 0,
    stopped: false,
    start: (total: number): void => {
      reporter.totals.push(total);
    },
    tick: (): void => {
      reporter.ticks += 1;
    },
    stop: (): void => {
      reporter.stopped = true;
    },
  };
  return reporter;
}

/** Canned `IShell` — returns a fixed platform string or throws the configured failure. */
export class FakeShell implements IShell {
  constructor(private readonly result: string | Error) {}

  async platform(): Promise<string> {
    if (this.result instanceof Error) throw this.result;
    return this.result;
  }
}

/** Canned `IPrompt` — answers every question with the configured value. */
export class FakePrompt implements IPrompt {
  constructor(private readonly answer: string) {}

  async ask(_message: string): Promise<string> {
    return this.answer;
  }
}
