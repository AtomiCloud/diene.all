import { expectSuccess } from './lib/exec.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-infisical-full-green',
      description: 'The full Infisical scanning hook passes tracked content.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-infisical --all-files', 'hook-infisical-full');
      },
    },
    {
      name: 'mutation-hook-infisical-full-caught',
      description: 'A focused sabotage must turn the hook-infisical-full mechanism red.',
      kind: 'mutation',
      // Nothing else reads this sabotage any more: the two secrets features that used to
      // share it (`secret-guards`, `secret-scan-command`) were deleted with the
      // fetch/scan actions of scripts/local/secrets.sh that they tested.
      expectedImpact: [],
      async run(repo: any) {
        const secret = ['AKIA', 'ABCDEFGHIJKLMNOP'].join('');
        await repo.write('probe-secret.txt', `aws_access_key_id=${secret}\n`);
        // The assertion below scans git history, so a commit that never lands leaves it
        // nothing to find. Discarding this exit code did not make the arm green - it made it
        // red for the wrong reason, reporting that the secret scanner stayed green after a
        // sabotage that never happened. The commit is the failure-prone step: the installed
        // pre-commit and commit-msg hooks refuse a staged secret and the subject
        // `probe-secret`, so asserting it here is what names the real cause.
        await expectSuccess(
          repo,
          'git add probe-secret.txt && git -c user.name=Probe -c user.email=probe@example.invalid commit -qm probe-secret',
        );
        await expectRed(repo, 'nix develop .#ci -c pre-commit run a-infisical --all-files', 'hook-infisical-full');
      },
    },
  ],
};
