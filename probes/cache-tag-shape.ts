import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-cache-tag-shape-green',
      description: 'Every nscloud cached job uses the single S31 org/OS/architecture tag.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/cache-tags.sh', 'cache-tag-shape');
      },
    },
    {
      name: 'mutation-cache-tag-shape-caught',
      description: 'A focused sabotage must turn the cache-tag-shape mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/workflows/reusable-precommit.yaml', {
          find: 'nscloud-cache-tag-atomi-nix-store-cache-linux-amd64',
          replace: 'nscloud-cache-tag-atomi-nix-store-cache',
        });
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/cache-tags.sh', 'cache-tag-shape');
      },
    },
  ],
};
