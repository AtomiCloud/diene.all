import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-secret-guards-green',
      description: 'The secrets script has a healthy local scan path.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/secrets.sh scan', 'secret-guards');
      },
    },
    {
      name: 'mutation-secret-guards-caught',
      description: 'A focused sabotage must turn the secret-guards mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const result = await repo.exec(
          'env -u INFISICAL_PROJECT_ID -u INFISICAL_ENVIRONMENT nix develop .#ci -c ./scripts/local/secrets.sh fetch',
        );
        if (result.exitCode === 0 || !result.stderr.includes('❌')) {
          throw new Error('the required-environment guard did not fail clearly');
        }
      },
    },
  ],
};
