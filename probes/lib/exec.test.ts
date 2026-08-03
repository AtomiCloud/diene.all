import { describe, expect, test } from 'bun:test';
import type { ProbeRepo } from '@cyanprint/contracts';
import { expectDevShellFailure, expectFailure } from './exec';

function fakeRepo(result: { exitCode: number; stdout?: string; stderr?: string }) {
  const commands: string[] = [];
  return {
    commands,
    repo: {
      async exec(command: string) {
        commands.push(command);
        return { exitCode: result.exitCode, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
      },
    } as ProbeRepo,
  };
}

describe('expectFailure', () => {
  test('accepts a failure only when its output contains the declared reason', async () => {
    const { repo } = fakeRepo({ exitCode: 1, stderr: 'specific refusal\n' });

    await expect(expectFailure(repo, 'gate', ['specific refusal'])).resolves.toMatchObject({ exitCode: 1 });
  });

  test('does not execute an expectation with no declared reason', async () => {
    const { repo, commands } = fakeRepo({ exitCode: 1 });

    await expect(expectFailure(repo, 'gate', [])).rejects.toThrow('has no declared reason');
    expect(commands).toHaveLength(0);
  });

  test('rejects a failure whose output lacks the declared reason', async () => {
    const { repo } = fakeRepo({ exitCode: 2, stderr: 'parse failed\n' });

    await expect(expectFailure(repo, 'gate', ['specific refusal'])).rejects.toThrow(
      'went red for the wrong reason (missing: specific refusal)',
    );
  });

  for (const exitCode of [126, 127]) {
    test(`rejects reserved unexecuted exit ${exitCode}`, async () => {
      const { repo } = fakeRepo({ exitCode, stderr: 'specific refusal\n' });

      await expect(expectFailure(repo, 'gate', ['specific refusal'])).rejects.toThrow(`exit ${exitCode}`);
    });
  }

  test('keeps the declared reason when wrapping a dev-shell command', async () => {
    const { repo, commands } = fakeRepo({ exitCode: 1, stderr: 'specific refusal\n' });

    await expectDevShellFailure(repo, 'gate', ['specific refusal']);

    expect(commands[0]).toContain("nix develop --no-write-lock-file .#ci -c bash -lc 'gate'");
  });
});
