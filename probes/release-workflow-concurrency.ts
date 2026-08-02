import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-workflow-concurrency-green',
      description: 'Release uses the single release concurrency group.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/validate/workflows.sh release-concurrency',
          'release-workflow-concurrency',
        );
      },
    },
    {
      name: 'mutation-release-workflow-concurrency-caught',
      description: 'A focused sabotage must turn the release-workflow-concurrency mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/workflows/release.yaml', { find: '  group: release', replace: '  group: broken' });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/validate/workflows.sh release-concurrency',
          'release-workflow-concurrency',
        );
      },
    },
  ],
};
