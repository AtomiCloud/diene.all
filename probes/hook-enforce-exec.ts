import { capturedEnvCommand, expectGreen } from './lib/helpers.ts';

// The arm needs a TRACKED shell script whose executable bit it can clear, and any one
// will do. It used to borrow scripts/validate/workflows.sh on the grounds that the file
// could not be lost; subjects have since been deleted out from under this arm twice, so
// the arm writes and tracks its own instead. Ownership is what keeps a subject present,
// not a belief about permanence.
const execBitSubject = `#!/usr/bin/env bash
# Fixture owned by the hook-enforce-exec mutation arm. Written, tracked and removed
# inside the arm; it is never committed.
set -euo pipefail

echo "hook-enforce-exec probe subject"
`;

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
        // The mechanism is that a tracked *.sh loses its executable bit, so the arm's own
        // fixture proves it exactly as a borrowed repository script did - and cannot be
        // removed by somebody else's change.
        const target = 'probe-enforce-exec-subject.sh';
        await repo.write(target, execBitSubject);
        try {
          // Tracking it is the point: the check inspects TRACKED scripts, so an untracked
          // fixture would leave the gate inspecting the same files it already did and the
          // arm would prove nothing.
          const staged = await repo.exec(`chmod +x ${target} && git add ${target}`);
          if (staged.exitCode !== 0) {
            throw new Error(`could not stage the exec-bit fixture: ${staged.stderr || staged.stdout}`);
          }
          // The sabotage is unstaged on purpose: an `--all-files` run reads the worktree,
          // so a bare `chmod` reaches the gate.
          const sabotaged = await repo.exec(`chmod -x ${target}`);
          if (sabotaged.exitCode !== 0) {
            throw new Error(`could not clear the executable bit on ${target}: ${sabotaged.stderr || sabotaged.stdout}`);
          }
          const result = await repo.exec(
            capturedEnvCommand('nix develop .#ci -c pre-commit run a-enforce-exec --all-files', 'hook-enforce-exec'),
            { timeoutMs: 240000 },
          );
          if (result.exitCode === 0) {
            throw new Error('hook-enforce-exec stayed green after sabotage');
          }
          // A non-zero exit is also what a hook that failed to start looks like, and it is
          // what a gate inspecting a smaller world looks like too, so the refusal has to
          // name the file it is refusing.
          if (!`${result.stdout}${result.stderr}`.includes(`'${target}' is tracked but not executable`)) {
            throw new Error(
              `hook-enforce-exec refused without naming the non-executable script: ${result.stdout}${result.stderr}`,
            );
          }
        } finally {
          await repo.exec(`git reset -q -- ${target}`);
          await repo.remove(target);
        }
      },
    },
  ],
};
