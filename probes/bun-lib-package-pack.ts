import { defineSmoke } from './lib/definition.ts';
import { packBunLibrary } from './lib/bun-package.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-package-pack-green',
    description: 'bun pm pack produces an installable library tarball.',
    async run(repo: any) {
      await packBunLibrary(repo, 'bun-lib-package-pack');
      if ((await repo.glob('pkg.tgz')).length !== 1) throw new Error('pkg.tgz is missing');
    },
  },
});
