import { defineSmoke } from './lib/definition.ts';
import { expectGreenOrOffline } from './wrapper-offline.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-dependency-update-green',
    description: 'Helm dependency update resolves the real pinned upstream.',
    async run(repo: any) {
      await expectGreenOrOffline(
        repo,
        'nix develop .#default -c helm dependency update chart',
        'wrapper-dependency-update',
      );
    },
  },
});
