import { defineGate } from './lib/definition.ts';
import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';
import { packBunLibrary } from './lib/bun-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-publint-green',
    description: 'publint strict independently validates the packed package.',
    async run(repo: any) {
      await packBunLibrary(repo, 'bun-lib-publint-pack');
      await expectBunGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-package.sh publint pkg.tgz',
        'bun-lib-publint',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-publint-caught',
    description: 'Pointing the import export at a missing artifact turns publint strict red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('package.json', {
        find: '"default": "./dist/index.js"',
        replace: '"default": "./dist/missing.js"',
      });
      await packBunLibrary(repo, 'bun-lib-publint-mutation-pack');
      await expectBunRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-package.sh publint pkg.tgz',
        'bun-lib-publint',
      );
    },
  },
});
