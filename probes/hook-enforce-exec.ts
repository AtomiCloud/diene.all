import { capturedEnvCommand, expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-enforce-exec-green',
      description: 'The generated executable-bit hook passes tracked shell scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-enforce-exec --all-files', 'hook-enforce-exec');
      },
    },
    {
      name: 'mutation-hook-enforce-exec-caught',
      description: 'A focused sabotage must turn the hook-enforce-exec mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The subject was `scripts/release/bump.sh`, then the freshness validator, and
        // both were deleted - the second by the move to `dlint skills-fresh`. The
        // mechanism is unchanged throughout: a tracked *.sh loses its executable bit.
        // So this points at the surviving validator, which the workspace cannot lose
        // because each of its two release-policy modes has its own probe.
        const target = 'scripts/validate/workflows.sh';
        // Unstaged on purpose, and measured rather than assumed: an `--all-files` run reads
        // the worktree, so a bare `chmod` reaches the gate. Staging the mode change as well
        // was tried and is redundant.
        const sabotaged = await repo.exec(`chmod -x ${target}`);
        if (sabotaged.exitCode !== 0) {
          throw new Error(`could not clear the executable bit: ${sabotaged.stderr || sabotaged.stdout}`);
        }
        const result = await repo.exec(
          capturedEnvCommand('nix develop .#ci -c pre-commit run a-enforce-exec --all-files', 'hook-enforce-exec'),
          { timeoutMs: 240000 },
        );
        if (result.exitCode === 0) {
          throw new Error('hook-enforce-exec stayed green after sabotage');
        }
        // A non-zero exit is also what a hook that failed to start looks like, so the
        // refusal has to name the file it is refusing.
        if (!`${result.stdout}${result.stderr}`.includes(`'${target}' is tracked but not executable`)) {
          throw new Error(
            `hook-enforce-exec refused without naming the non-executable script: ${result.stdout}${result.stderr}`,
          );
        }
      },
    },
  ],
};
