import { describe, expect, test } from 'bun:test';
import type { MercuryApplication, MercuryDbInitResult } from '../../../src/composition/application.ts';
import {
  MERCURY_USAGE,
  type MercuryCliOptions,
  type MercuryCliSignals,
  mercuryCommands,
  redactDiagnostic,
  runMercuryCli,
} from '../../../src/composition/cli.ts';
import type { MercuryConfig } from '../../../src/composition/config.ts';

interface Written {
  readonly stream: 'stderr' | 'stdout';
  readonly line: string;
}

const stubConfig = (landscape = 'base', port = 8080): MercuryConfig => {
  const blocks: Record<string, unknown> = { app: { landscape, port } };
  const accessor = (key: string): unknown => blocks[key];
  return Object.assign(accessor, {
    get: accessor,
    all: () => blocks,
  }) as unknown as MercuryConfig;
};

class RecordingSignals implements MercuryCliSignals {
  readonly handlers = new Map<'SIGINT' | 'SIGTERM', Set<() => void>>();

  on(signal: 'SIGINT' | 'SIGTERM', handler: () => void): void {
    const existing = this.handlers.get(signal) ?? new Set<() => void>();
    existing.add(handler);
    this.handlers.set(signal, existing);
  }

  off(signal: 'SIGINT' | 'SIGTERM', handler: () => void): void {
    this.handlers.get(signal)?.delete(handler);
  }

  raise(signal: 'SIGINT' | 'SIGTERM'): void {
    for (const handler of [...(this.handlers.get(signal) ?? [])]) {
      handler();
    }
  }

  get registered(): number {
    let total = 0;
    for (const handlers of this.handlers.values()) {
      total += handlers.size;
    }
    return total;
  }
}

const fakeApplication = (
  calls: string[],
  behaviour: { readonly startError?: Error; readonly shutdownError?: Error } = {},
): MercuryApplication =>
  ({
    config: stubConfig(),
    registry: undefined,
    supervisor: undefined,
    router: undefined,
    fetch: async () => new Response(null),
    startupComplete: () => true,
    readiness: async () => ({ ready: true, dependencies: {} }),
    start: async () => {
      calls.push('start');
      if (behaviour.startError !== undefined) {
        throw behaviour.startError;
      }
    },
    shutdown: async () => {
      calls.push('shutdown');
      if (behaviour.shutdownError !== undefined) {
        throw behaviour.shutdownError;
      }
    },
  }) as unknown as MercuryApplication;

const capture = (): { readonly written: Written[]; readonly write: MercuryCliOptions['write'] } => {
  const written: Written[] = [];
  return { written, write: (stream, line) => written.push({ stream, line }) };
};

describe('Mercury CLI dispatch', () => {
  test('accepts exactly the two published commands', () => {
    expect([...mercuryCommands]).toEqual(['db-init', 'serve']);
  });

  test.each([[[]], [['serve', 'extra']], [['migrate']], [['--help']], [['SERVE']]])(
    'fails closed on invalid argv %j',
    async argv => {
      const { written, write } = capture();
      let loaded = false;
      const code = await runMercuryCli(argv, {
        write,
        loadConfig: async () => {
          loaded = true;
          return stubConfig();
        },
      });

      expect(code).toBe(2);
      expect(loaded).toBe(false);
      expect(written).toEqual([{ stream: 'stderr', line: MERCURY_USAGE }]);
    },
  );

  test('fails closed when configuration cannot be loaded', async () => {
    const { written, write } = capture();
    const code = await runMercuryCli(['serve'], {
      write,
      loadConfig: async () => {
        throw new Error('security.consoleSessionSecretFile is required');
      },
    });

    expect(code).toBe(78);
    expect(written[0]?.stream).toBe('stderr');
    expect(written[0]?.line).toContain('configuration is invalid');
  });

  test('fails closed when composition rejects a security input', async () => {
    const { written, write } = capture();
    const calls: string[] = [];
    const code = await runMercuryCli(['serve'], {
      write,
      loadConfig: async () => stubConfig(),
      createApplication: async () => {
        throw new Error('console authorization key pair does not match');
      },
      dbInit: async () => {
        calls.push('db-init');
        return { migrations: [], accountId: '', credentialIssued: false };
      },
    });

    expect(code).toBe(78);
    expect(calls).toEqual([]);
    expect(written.some(entry => entry.line.includes('composition failed'))).toBe(true);
  });
});

describe('Mercury CLI serve lifecycle', () => {
  test('serves until a termination signal and then shuts down cleanly', async () => {
    const calls: string[] = [];
    const signals = new RecordingSignals();
    const { written, write } = capture();
    const pending = runMercuryCli(['serve'], {
      write,
      signals,
      loadConfig: async () => stubConfig('prod', 9090),
      createApplication: async () => fakeApplication(calls),
    });

    await Bun.sleep(0);
    expect(calls).toEqual(['start']);
    signals.raise('SIGTERM');

    expect(await pending).toBe(0);
    expect(calls).toEqual(['start', 'shutdown']);
    expect(signals.registered).toBe(0);
    expect(written.some(entry => entry.line.includes('serving prod on port 9090'))).toBe(true);
  });

  test('shuts down and reports failure when startup fails closed', async () => {
    const calls: string[] = [];
    const signals = new RecordingSignals();
    const { written, write } = capture();

    const code = await runMercuryCli(['serve'], {
      write,
      signals,
      loadConfig: async () => stubConfig(),
      createApplication: async () =>
        fakeApplication(calls, { startError: new Error('a compiled endpoint signing secret is unavailable') }),
    });

    expect(code).toBe(1);
    expect(calls).toEqual(['start', 'shutdown']);
    expect(written.some(entry => entry.line.includes('startup failed'))).toBe(true);
  });

  test('reports a failing shutdown without masking it as success', async () => {
    const calls: string[] = [];
    const signals = new RecordingSignals();
    const { written, write } = capture();
    const pending = runMercuryCli(['serve'], {
      write,
      signals,
      loadConfig: async () => stubConfig(),
      createApplication: async () => fakeApplication(calls, { shutdownError: new Error('redis quit failed') }),
    });

    await Bun.sleep(0);
    signals.raise('SIGINT');

    expect(await pending).toBe(1);
    expect(written.some(entry => entry.line.includes('shutdown failed'))).toBe(true);
  });
});

describe('Mercury CLI db-init', () => {
  test('runs migrations and bootstraps without echoing the token', async () => {
    const { written, write } = capture();
    const result: MercuryDbInitResult = {
      migrations: ['001_mercury_management.sql', '002_provider_operation_state.sql'],
      accountId: 'account-1',
      credentialIssued: true,
    };
    let received: MercuryConfig | undefined;

    const code = await runMercuryCli(['db-init'], {
      write,
      loadConfig: async () => stubConfig(),
      dbInit: async config => {
        received = config;
        return result;
      },
      createApplication: async () => {
        throw new Error('serve must not be composed for db-init');
      },
    });

    expect(code).toBe(0);
    expect(received).toBeDefined();
    expect(written).toEqual([
      {
        stream: 'stdout',
        line: 'mercury: db-init applied 2 migration(s); default internal account ready',
      },
    ]);
  });

  test('returns a failure code when bootstrap material is unusable', async () => {
    const { written, write } = capture();
    const code = await runMercuryCli(['db-init'], {
      write,
      loadConfig: async () => stubConfig(),
      dbInit: async () => {
        throw new Error('management bootstrap token is invalid');
      },
    });

    expect(code).toBe(1);
    expect(written[0]?.line).toContain('db-init failed');
  });
});

describe('Mercury CLI diagnostics redaction', () => {
  test('never emits vault pointers, mount paths, or connection strings', () => {
    const redacted = redactDiagnostic(
      'secret /mercury/providers/stripe missing at /var/run/secrets/mercury/console-session for postgres://user:pw@db:5432/mercury',
    );

    expect(redacted).not.toContain('/mercury/providers/stripe');
    expect(redacted).not.toContain('/var/run/secrets');
    expect(redacted).not.toContain('postgres://');
    expect(redacted).toContain('[redacted-path]');
    expect(redacted).toContain('[redacted-url]');
  });

  test('redacts pointers surfaced through a failing command', async () => {
    const { written, write } = capture();
    await runMercuryCli(['db-init'], {
      write,
      loadConfig: async () => stubConfig(),
      dbInit: async () => {
        throw new Error('cannot read /var/run/secrets/mercury/management-bootstrap-token');
      },
    });

    expect(written[0]?.line).not.toContain('/var/run/secrets');
    expect(written[0]?.line).toContain('[redacted-path]');
  });

  test('leaves ordinary prose untouched', () => {
    expect(redactDiagnostic('management bootstrap token is invalid')).toBe('management bootstrap token is invalid');
  });
});
