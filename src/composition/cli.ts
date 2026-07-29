import {
  createMercuryApplication,
  type MercuryApplication,
  type MercuryCompositionSeams,
  type MercuryDbInitResult,
  runMercuryDbInit,
} from './application.ts';
import { loadMercuryConfig, type MercuryConfig, type MercuryConfigLoadOptions } from './config.ts';

export const mercuryCommands = ['db-init', 'serve'] as const;

export type MercuryCommand = (typeof mercuryCommands)[number];

export const MERCURY_USAGE = 'usage: mercury <serve|db-init>';

export interface MercuryCliSignals {
  on(signal: 'SIGINT' | 'SIGTERM', handler: () => void): void;
  off(signal: 'SIGINT' | 'SIGTERM', handler: () => void): void;
}

export interface MercuryCliOptions {
  readonly config?: MercuryConfigLoadOptions;
  readonly seams?: MercuryCompositionSeams & { readonly migrationsDirectory?: string };
  readonly loadConfig?: (options: MercuryConfigLoadOptions) => Promise<MercuryConfig>;
  readonly createApplication?: (config: MercuryConfig, seams: MercuryCompositionSeams) => Promise<MercuryApplication>;
  readonly dbInit?: (
    config: MercuryConfig,
    seams: MercuryCompositionSeams & { readonly migrationsDirectory?: string },
  ) => Promise<MercuryDbInitResult>;
  readonly signals?: MercuryCliSignals;
  readonly write?: (stream: 'stderr' | 'stdout', line: string) => void;
}

const absolutePathPattern = /(?:^|(?<=[\s"'(=]))\/(?:[^\s"'),;]+)/g;
const urlPattern = /\b[a-z][a-z0-9+.-]*:\/\/[^\s"'),;]+/gi;

/**
 * Diagnostics may quote vault pointers, mounted paths, or connection strings.
 * They are redacted before anything reaches an operator's log stream.
 */
export function redactDiagnostic(message: string): string {
  return message.replace(urlPattern, '[redacted-url]').replace(absolutePathPattern, '[redacted-path]');
}

const describe = (error: unknown): string =>
  redactDiagnostic(error instanceof Error ? error.message : 'unexpected failure');

const parseCommand = (argv: readonly string[]): MercuryCommand | undefined => {
  if (argv.length !== 1) {
    return undefined;
  }
  const [candidate] = argv;
  return mercuryCommands.find(command => command === candidate);
};

const defaultSignals: MercuryCliSignals = {
  on: (signal, handler) => {
    process.on(signal, handler);
  },
  off: (signal, handler) => {
    process.off(signal, handler);
  },
};

const defaultWrite = (stream: 'stderr' | 'stdout', line: string): void => {
  if (stream === 'stderr') {
    process.stderr.write(`${line}\n`);
    return;
  }
  process.stdout.write(`${line}\n`);
};

const awaitTermination = (signals: MercuryCliSignals): Promise<void> =>
  new Promise<void>(resolve => {
    const stop = (): void => {
      signals.off('SIGINT', stop);
      signals.off('SIGTERM', stop);
      resolve();
    };
    signals.on('SIGINT', stop);
    signals.on('SIGTERM', stop);
  });

/**
 * The only executable surface: exactly `serve` or `db-init`, failing closed on
 * any invalid command, configuration, or security input. Nothing written here
 * carries secret content or secret pointers.
 */
export async function runMercuryCli(argv: readonly string[], options: MercuryCliOptions = {}): Promise<number> {
  const write = options.write ?? defaultWrite;
  const command = parseCommand(argv);
  if (command === undefined) {
    write('stderr', MERCURY_USAGE);
    return 2;
  }

  let config: MercuryConfig;
  try {
    config = await (options.loadConfig ?? loadMercuryConfig)(options.config ?? {});
  } catch (error) {
    write('stderr', `mercury: configuration is invalid: ${describe(error)}`);
    return 78;
  }

  const seams = options.seams ?? {};
  if (command === 'db-init') {
    try {
      const result = await (options.dbInit ?? runMercuryDbInit)(config, seams);
      write(
        'stdout',
        `mercury: db-init applied ${result.migrations.length} migration(s); default internal account ready`,
      );
      return 0;
    } catch (error) {
      write('stderr', `mercury: db-init failed: ${describe(error)}`);
      return 1;
    }
  }

  let application: MercuryApplication;
  try {
    application = await (options.createApplication ?? createMercuryApplication)(config, seams);
  } catch (error) {
    write('stderr', `mercury: composition failed: ${describe(error)}`);
    return 78;
  }

  const signals = options.signals ?? defaultSignals;
  const termination = awaitTermination(signals);
  try {
    await application.start();
  } catch (error) {
    write('stderr', `mercury: startup failed: ${describe(error)}`);
    await application.shutdown().catch(() => undefined);
    return 1;
  }

  write('stdout', `mercury: serving ${config('app').landscape} on port ${config('app').port}`);
  await termination;
  try {
    await application.shutdown();
  } catch (error) {
    write('stderr', `mercury: shutdown failed: ${describe(error)}`);
    return 1;
  }
  return 0;
}
