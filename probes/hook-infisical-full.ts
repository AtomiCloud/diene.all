import { expectGreen, expectRedBecause } from './lib/helpers.ts';

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
        await repo.exec(
          'git add probe-secret.txt && git -c user.name=Probe -c user.email=probe@example.invalid commit -qm probe-secret',
        );
        await expectRedBecause(
          repo,
          'nix develop .#ci -c pre-commit run a-infisical --all-files',
          'hook-infisical-full',
          ['- hook id: a-infisical', 'probe-secret.txt:aws-access-token'],
        );
      },
    },
  ],
};
