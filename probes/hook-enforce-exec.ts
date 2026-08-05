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
        // The subject was `scripts/release/bump.sh` until the release bump machinery was
        // deleted. The mechanism is unchanged - a tracked *.sh loses its executable bit -
        // so this points at a script the workspace cannot lose: the freshness validator
        // the skills gate calls.
        const target = 'scripts/validate/skills-freshness.sh';
        // The mode change is staged as well as applied: pre-commit sets unstaged changes
        // aside before it runs a hook, and a bare `chmod` is exactly such a change, so an
        // unstaged sabotage can be filed away before the gate ever sees it.
        const sabotaged = await repo.exec(`chmod -x ${target} && git update-index --chmod=-x ${target}`);
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
