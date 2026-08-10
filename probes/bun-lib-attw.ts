import { defineGate } from './lib/definition.ts';
import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';
import { packBunLibrary } from './lib/bun-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-attw-green',
    description: 'Are The Types Wrong independently validates import and require type resolution.',
    async run(repo: any) {
      await packBunLibrary(repo, 'bun-lib-attw-pack');
      await expectBunGreen(repo, 'nix develop .#ci -c ./scripts/validate/bun-package.sh attw pkg.tgz', 'bun-lib-attw');
    },
  },
  mutation: {
    name: 'mutation-bun-lib-attw-caught',
    description: 'Mapping require.types to the ESM declaration kind turns attw red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('package.json', {
        find: '"types": "./dist/index.d.cts"',
        replace: '"types": "./dist/index.d.ts"',
      });
      await packBunLibrary(repo, 'bun-lib-attw-mutation-pack');
      await expectBunRed(repo, 'nix develop .#ci -c ./scripts/validate/bun-package.sh attw pkg.tgz', 'bun-lib-attw');
    },
  },
});
