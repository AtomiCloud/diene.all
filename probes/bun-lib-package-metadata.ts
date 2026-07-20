import { defineGate } from './lib/definition.ts';
import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';
import { packBunLibrary } from './lib/bun-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-package-metadata-green',
    description: 'The packed manifest identity and root MIT license agree.',
    async run(repo: any) {
      await packBunLibrary(repo, 'bun-lib-package-metadata-pack');
      await expectBunGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-package.sh metadata pkg.tgz',
        'bun-lib-package-metadata',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-package-metadata-caught',
    description: 'Mismatching the manifest license from the root LICENSE turns metadata validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('package.json', { find: '"license": "MIT"', replace: '"license": "Apache-2.0"' });
      await packBunLibrary(repo, 'bun-lib-package-metadata-mutation-pack');
      await expectBunRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-package.sh metadata pkg.tgz',
        'bun-lib-package-metadata',
      );
    },
  },
});
