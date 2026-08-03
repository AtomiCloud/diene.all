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
      expectedImpact: ['secret-guards', 'secret-scan-command'],
      async run(repo: any) {
        const secret = ['AKIA', 'ABCDEFGHIJKLMNOP'].join('');
        await repo.write('probe-secret.txt', `aws_access_key_id=${secret}\n`);
        // Seed the history fixture without letting the hook under test abort
        // its own setup; the explicit full scan below is the mechanism under test.
        await repo.exec(
          'git add probe-secret.txt && SKIP=a-infisical,a-infisical-staged git -c user.name=Probe -c user.email=probe@example.invalid commit -qm probe-secret',
        );
        await expectRed(repo, 'nix develop .#ci -c pre-commit run a-infisical --all-files', 'hook-infisical-full');
      },
    },
  ],
};
