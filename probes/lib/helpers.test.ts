import { describe, expect, test } from 'bun:test';
import { expectRedBecause } from './helpers';

type Recorded = { command: string; options?: { timeoutMs?: number } };

function fakeRepo(result: { exitCode: number; stdout?: string; stderr?: string }) {
  const calls: Recorded[] = [];
  return {
    calls,
    async exec(command: string, options?: { timeoutMs?: number }) {
      calls.push({ command, options });
      return { exitCode: result.exitCode, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
    },
  };
}

// Assert-the-asserter: every arm is driven on a known-bad case as well as a known-good one.
describe('expectRedBecause', () => {
  test('accepts a red whose output names every declared reason', async () => {
    const repo = fakeRepo({ exitCode: 1, stdout: 'error TS2322: Type mismatch\n' });

    const actual = await expectRedBecause(repo, 'tsc --noEmit', 'typecheck', ['error TS2322']);

    expect(actual).toContain('error TS2322');
    expect(repo.calls[0].command).toBe('tsc --noEmit');
  });

  test('reads the reason out of stderr as well as stdout', async () => {
    const repo = fakeRepo({ exitCode: 2, stderr: 'lint/suspicious/noDoubleEquals\n' });

    await expect(expectRedBecause(repo, 'biome lint', 'biome', ['lint/suspicious/noDoubleEquals'])).resolves.toContain(
      'noDoubleEquals',
    );
  });

  test('rejects a green run', async () => {
    const repo = fakeRepo({ exitCode: 0, stdout: 'error TS2322\n' });

    await expect(expectRedBecause(repo, 'tsc --noEmit', 'typecheck', ['error TS2322'])).rejects.toThrow(
      'typecheck stayed green after sabotage',
    );
  });

  test('rejects a red whose output is missing a declared reason', async () => {
    const repo = fakeRepo({ exitCode: 1, stdout: 'Killed: out of memory\n' });

    await expect(expectRedBecause(repo, 'tsc --noEmit', 'typecheck', ['error TS2322'])).rejects.toThrow(
      'typecheck went red for the wrong reason (missing: error TS2322)',
    );
  });

  test('reports every missing reason, not only the first', async () => {
    const repo = fakeRepo({ exitCode: 1, stdout: 'Unused files (1)\n' });

    await expect(
      expectRedBecause(repo, 'knip', 'knip-production', ['Unused files', 'src/lib/a.ts', 'src/lib/b.ts']),
    ).rejects.toThrow('missing: src/lib/a.ts, src/lib/b.ts');
  });

  test('rejects a red that arrived through a disqualified path', async () => {
    const repo = fakeRepo({ exitCode: 1, stdout: '10 pass\n1 fail\ncoverage below threshold\n' });

    await expect(
      expectRedBecause(repo, 'bun test --coverage', 'unit-coverage', ['coverage below threshold'], {
        forbidden: ['1 fail'],
      }),
    ).rejects.toThrow('unit-coverage went red through a disqualified path (found: 1 fail)');
  });

  test('accepts a red when no disqualifying marker is present', async () => {
    const repo = fakeRepo({ exitCode: 1, stdout: '10 pass\n0 fail\ncoverage below threshold\n' });

    await expect(
      expectRedBecause(repo, 'bun test --coverage', 'unit-coverage', ['coverage below threshold'], {
        forbidden: ['1 fail'],
      }),
    ).resolves.toContain('0 fail');
  });

  test('refuses to run with no reason at all, so it can never pass vacuously', async () => {
    const repo = fakeRepo({ exitCode: 1 });

    await expect(expectRedBecause(repo, 'anything', 'vacuous', [])).rejects.toThrow(
      'vacuous: expectRedBecause was given no refusal reason',
    );
    expect(repo.calls).toHaveLength(0);
  });

  test('passes the caller timeout through to the sandbox', async () => {
    const repo = fakeRepo({ exitCode: 1, stdout: 'reason\n' });

    await expectRedBecause(repo, 'slow', 'slow', ['reason'], { timeoutMs: 900_000 });

    expect(repo.calls[0].options).toEqual({ timeoutMs: 900_000 });
  });

  for (const exitCode of [126, 127]) {
    test(`rejects reserved unexecuted exit ${exitCode} even when output contains the expected reason`, async () => {
      const repo = fakeRepo({ exitCode, stderr: 'error TS2322\n' });

      await expect(expectRedBecause(repo, 'tsc --noEmit', 'typecheck', ['error TS2322'])).rejects.toThrow(
        `exit ${exitCode}`,
      );
    });
  }
});
