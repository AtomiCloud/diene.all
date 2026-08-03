import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-infisical-staged-green',
      description: 'The staged-diff Infisical hook passes the untouched index.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c pre-commit run a-infisical-staged --all-files',
          'hook-infisical-staged',
        );
      },
    },
    {
      name: 'mutation-hook-infisical-staged-caught',
      description: 'A focused sabotage must turn the hook-infisical-staged mechanism red.',
      kind: 'mutation',
      expectedImpact: ['hook-infisical-full', 'secret-scan-command'],
      async run(repo: any) {
        const secret = ['AKIA', 'QRSTUVWXYZABCDEF'].join('');
        await repo.write('probe-secret.txt', `aws_access_key_id=${secret}\n`);
        await repo.exec('git add probe-secret.txt');
        await expectRedBecause(
          repo,
          'nix develop .#ci -c pre-commit run a-infisical-staged --all-files',
          'hook-infisical-staged',
          ['probe-secret.txt', 'aws-access-token'],
        );
      },
    },
  ],
};
