import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-publish-git-green',
    description: 'The secondary git chart-repository package and index dry-run succeeds.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#cd -c ./scripts/validate/helm-wrapper.sh publish-git',
        'wrapper-publish-git',
      );
    },
  },
});
