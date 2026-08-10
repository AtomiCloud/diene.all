import { describe, it } from 'bun:test';
import { rm } from 'node:fs/promises';
import { resolve } from 'node:path';
import should from 'should';

/** Drive the same fixture command green and sabotaged to prove the threshold blocks. */
const REPOSITORY_ROOT = resolve(import.meta.dir, '../..');
const FIXTURE_CONFIG = 'tests/fixtures/coverage-gate/bunfig.toml';
const FIXTURE_COVERAGE_DIR = 'coverage/fixture';
const FIXTURE_ARTIFACT = `${FIXTURE_COVERAGE_DIR}/lcov.info`;

interface GateRun {
  readonly exitCode: number;
  readonly output: string;
}

async function runGate(sabotage: boolean): Promise<GateRun> {
  await rm(resolve(REPOSITORY_ROOT, FIXTURE_COVERAGE_DIR), { recursive: true, force: true });

  const process_ = Bun.spawn([process.execPath, 'test', `--config=${FIXTURE_CONFIG}`, '--coverage'], {
    cwd: REPOSITORY_ROOT,
    env: { ...process.env, COVERAGE_GATE_SABOTAGE: sabotage ? '1' : '0' },
    stdout: 'pipe',
    stderr: 'pipe',
  });

  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(process_.stdout).text(),
    new Response(process_.stderr).text(),
    process_.exited,
  ]);

  return { exitCode, output: `${stdout}${stderr}` };
}

describe('coverage threshold gate', () => {
  it('should pass and write a scoped lcov artifact when the fixture suite is intact', async () => {
    // Act
    const actual = await runGate(false);

    // Assert
    should(actual.exitCode).equal(0, actual.output);
    should(actual.output).match(/0 fail/);
    should(await Bun.file(resolve(REPOSITORY_ROOT, FIXTURE_ARTIFACT)).exists()).be.true();
  }, 120_000);

  it('should fail when a test is skipped, even though no test fails', async () => {
    // Act
    const actual = await runGate(true);

    // Assert
    should(actual.exitCode).equal(1, actual.output);
    should(actual.output).match(/0 fail/);
    should(actual.output).match(/1 skip/);
  }, 120_000);
});
