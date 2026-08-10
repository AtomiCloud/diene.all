import { defineGate } from './lib/definition.ts';
import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';
import { packBunLibrary } from './lib/bun-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-pack-content-green',
    description: 'The packed library contains every dual-format artifact and usage-skill asset.',
    async run(repo: any) {
      await packBunLibrary(repo, 'bun-lib-pack-content-pack');
      await expectBunGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-package.sh pack-content pkg.tgz',
        'bun-lib-pack-content',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-pack-content-caught',
    description: 'Removing the usage skill from the package allowlist turns content validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('package.json', { find: '    "dist",\n    "skills"', replace: '    "dist"' });
      await packBunLibrary(repo, 'bun-lib-pack-content-mutation-pack');
      await expectBunRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-package.sh pack-content pkg.tgz',
        'bun-lib-pack-content',
      );
    },
  },
});
