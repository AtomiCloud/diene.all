import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-cache-tag-shape-green',
      description: 'Every workflow selects one exact S31 venue label and rotates the Namespace cache tag with its OS.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/validate/workflows.sh cache-tag-shape',
          'cache-tag-shape',
        );
      },
    },
    {
      name: 'mutation-cache-tag-shape-caught',
      description: 'A 24.04 cache tag paired with the selected 26.04 Namespace runner must turn the S31 gate red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/workflows/⚡reusable-precommit.yaml', {
          find: 'nscloud-cache-tag-atomi-nix-store-cache-ubuntu-26.04-amd64',
          replace: 'nscloud-cache-tag-atomi-nix-store-cache-ubuntu-24.04-amd64',
        });
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/workflows.sh cache-tag-shape', 'cache-tag-shape');
      },
    },
  ],
};
