import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-type-vocabulary-green',
      description: 'The release type list equals the unified D3 vocabulary.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/validate/release-config.sh types',
          'release-type-vocabulary',
        );
      },
    },
    {
      name: 'mutation-release-type-vocabulary-caught',
      description: 'A focused sabotage must turn the release-type-vocabulary mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('atomi_release.yaml', { find: '  - type: chore', replace: '  - type: chores' });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/release-config.sh types',
          'release-type-vocabulary',
        );
      },
    },
  ],
};
