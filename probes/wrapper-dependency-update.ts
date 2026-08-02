import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-dependency-update-green',
    description: 'Helm dependency update resolves the real pinned upstream.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#default -c helm dependency update chart', 'wrapper-dependency-update');
    },
  },
});
