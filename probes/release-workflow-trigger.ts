import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-workflow-trigger-green',
      description: 'Release runs only after successful CI completion on main.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/validate/workflows.sh release-trigger',
          'release-workflow-trigger',
        );
      },
    },
    {
      name: 'mutation-release-workflow-trigger-caught',
      description: 'A focused sabotage must turn the release-workflow-trigger mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/workflows/release.yaml', {
          find: "workflows: ['CI']",
          replace: "workflows: ['Broken']",
        });
        await expectRedBecause(
          repo,
          'nix develop .#ci -c ./scripts/validate/workflows.sh release-trigger',
          'release-workflow-trigger',
          ['release must trigger from CI'],
        );
      },
    },
  ],
};
