import { afterAll, describe, expect, test } from 'bun:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { devShellCommand } from './exec';
import { capturedEnvCommand, DEV_SHELL_CHAIN, expectDevShellsOnce } from './helpers';

const ENV_DIR = '/captures';

// The four-shell chain dev-shell.ts asserts, verbatim.
const CHAINED =
  'nix develop --no-write-lock-file .#default -c true && nix develop --no-write-lock-file .#ci -c true && ' +
  'nix develop --no-write-lock-file .#cd -c true && nix develop --no-write-lock-file .#releaser -c true';

// A real corpus command whose payload is a single-quoted bash script containing its own
// escaped single quotes — the shape the rewrite is most likely to corrupt.
const EMBEDDED_QUOTES =
  `nix develop .#ci -c bash -c 'set -euo pipefail; first="$(mktemp -d)"; ` +
  `trap "rm -rf \\"$first\\"" EXIT; test "$(cat skill)" = '"'"'committed skill'"'"''`;

describe('captured-env rewrite — flag off is byte-identical', () => {
  const commands = [
    CHAINED,
    EMBEDDED_QUOTES,
    'nix develop .#ci -c helm lint infra/root_chart',
    'CI_DOCKER_PUSH=false nix develop .#cd -c ./scripts/ci/docker.sh',
    'nix fmt --no-write-lock-file -- --ci --formatters shfmt',
  ];

  for (const command of commands) {
    test(`unset PROBE_CAPTURED_ENV leaves the bytes alone: ${command.slice(0, 48)}`, () => {
      expect(capturedEnvCommand(command, 'any-label', undefined)).toBe(command);
    });
  }

  test('devShellCommand is unchanged with the flag off', () => {
    const previous = process.env.PROBE_CAPTURED_ENV;
    delete process.env.PROBE_CAPTURED_ENV;
    try {
      expect(devShellCommand(`printf '%s' "it's here"`, 'ci')).toBe(
        `nix develop --no-write-lock-file .#ci -c bash -lc 'printf '"'"'%s'"'"' "it'"'"'s here"'`,
      );
    } finally {
      if (previous !== undefined) process.env.PROBE_CAPTURED_ENV = previous;
    }
  });
});

describe('captured-env rewrite — flag on', () => {
  test('the shells whose subject IS shell entry are exempt', () => {
    expect(capturedEnvCommand(CHAINED, 'dev-shell', ENV_DIR)).toBe(CHAINED);
    expect(capturedEnvCommand('nix develop .#ci -c true', 'direnv', ENV_DIR)).toBe('nix develop .#ci -c true');
  });

  test('both invocation variants are rewritten and the shell name selects the capture', () => {
    expect(capturedEnvCommand('nix develop .#ci -c helm lint infra/root_chart', 'helm-lint', ENV_DIR)).toContain(
      `probe-captured-env '/captures/ci.sh' helm lint infra/root_chart`,
    );
    expect(
      capturedEnvCommand('nix develop --no-write-lock-file .#default -c pre-commit run treefmt', 'fmt', ENV_DIR),
    ).toContain(`probe-captured-env '/captures/default.sh' pre-commit run treefmt`);
  });

  test('a chained command rewrites every occurrence and keeps the && structure', () => {
    const rewritten = capturedEnvCommand(CHAINED, 'chained', ENV_DIR);
    expect(rewritten.split('probe-captured-env').length - 1).toBe(4);
    expect(rewritten).not.toContain('nix develop');
    expect(rewritten.split(' && ').length).toBe(4);
    for (const shell of ['default', 'ci', 'cd', 'releaser']) {
      expect(rewritten).toContain(`'/captures/${shell}.sh' true`);
    }
  });

  test('everything after `-c ` is carried through byte-for-byte', () => {
    const payload = EMBEDDED_QUOTES.slice('nix develop .#ci -c '.length);
    expect(capturedEnvCommand(EMBEDDED_QUOTES, 'skills-sync', ENV_DIR).endsWith(payload)).toBe(true);
  });

  test('a capture directory containing a quote is escaped, not injected', () => {
    const rewritten = capturedEnvCommand('nix develop .#ci -c true', 'quoting', "/tmp/it's");
    expect(rewritten).toContain(`'/tmp/it'"'"'s/ci.sh'`);
  });

  test('devShellCommand is rewritten too', () => {
    const previous = process.env.PROBE_CAPTURED_ENV;
    process.env.PROBE_CAPTURED_ENV = ENV_DIR;
    try {
      expect(devShellCommand('true', 'cd')).toBe(
        capturedEnvCommand(`nix develop --no-write-lock-file .#cd -c bash -lc 'true'`, undefined, ENV_DIR),
      );
    } finally {
      if (previous === undefined) delete process.env.PROBE_CAPTURED_ENV;
      else process.env.PROBE_CAPTURED_ENV = previous;
    }
  });
});

describe('duplicate dev-shell proof', () => {
  test('one real shell chain proves both duplicate feature arms in one sandbox phase', async () => {
    const commands: string[] = [];
    const outcomes = [{ exitCode: 1 }, { exitCode: 0 }, { exitCode: 0 }, { exitCode: 0 }];
    const repo = {
      exec: async (command: string) => {
        commands.push(command);
        return outcomes.shift() ?? { exitCode: 1 };
      },
    };

    await expectDevShellsOnce(repo);
    await expectDevShellsOnce(repo);

    expect(DEV_SHELL_CHAIN).toBe(CHAINED);
    expect(commands.filter(command => command === DEV_SHELL_CHAIN)).toHaveLength(1);
    expect(commands).toEqual([
      '[ -f .git/cyanprint-probe-dev-shell-checked ]',
      DEV_SHELL_CHAIN,
      ': > .git/cyanprint-probe-dev-shell-checked',
      '[ -f .git/cyanprint-probe-dev-shell-checked ]',
    ]);
  });
});

// The byte assertions above cannot show that the rewritten string still *runs* the same
// argv. These do, against a hand-written capture, with no nix anywhere: `sh -c` is exactly
// how cyanprint's probe sandbox executes a probe command (packages/core/src/probe/spawn.ts).
describe('captured-env rewrite — the rewritten command actually runs', () => {
  const dir = mkdtempSync(join(tmpdir(), 'captured-env-test-'));
  writeFileSync(join(dir, 'ci.sh'), 'export PROBE_TEST_MARKER=from-capture\n');

  afterAll(() => rmSync(dir, { recursive: true, force: true }));

  async function run(command: string): Promise<{ code: number; stdout: string; stderr: string }> {
    const proc = Bun.spawn(['sh', '-c', command], { stdout: 'pipe', stderr: 'pipe' });
    const [stdout, stderr, code] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ]);
    return { code, stdout, stderr };
  }

  test('the capture is sourced and the payload argv survives intact', async () => {
    const command = capturedEnvCommand(`nix develop .#ci -c sh -c 'printf "%s" "$PROBE_TEST_MARKER"'`, 'marker', dir);
    expect(await run(command)).toMatchObject({ code: 0, stdout: 'from-capture' });
  });

  test('the corpus `bash -lc <shellQuote>` nesting survives the rewrite', async () => {
    const previous = process.env.PROBE_CAPTURED_ENV;
    process.env.PROBE_CAPTURED_ENV = dir;
    try {
      const result = await run(devShellCommand(`printf '%s' "it's here: $PROBE_TEST_MARKER"`, 'ci'));
      expect(result).toMatchObject({ code: 0, stdout: "it's here: from-capture" });
    } finally {
      if (previous === undefined) delete process.env.PROBE_CAPTURED_ENV;
      else process.env.PROBE_CAPTURED_ENV = previous;
    }
  });

  test('the payload exit code is the command exit code, not the wrapper', async () => {
    expect(await run(capturedEnvCommand('nix develop .#ci -c sh -c "exit 42"', 'exit', dir))).toMatchObject({
      code: 42,
    });
  });

  test('a missing capture fails loudly instead of running in the ambient environment', async () => {
    const result = await run(capturedEnvCommand('nix develop .#releaser -c true', 'missing', dir));
    expect(result.code).toBe(127);
    expect(result.stderr).toContain('captured env is not readable');
  });
});
