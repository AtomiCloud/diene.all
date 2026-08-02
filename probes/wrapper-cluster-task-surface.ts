import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-cluster-task-surface-green',
    description: 'The stacked landscape:cluster include exposes debug, template, install, and remove.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#default -c ./scripts/validate/helm-wrapper.sh task-surface',
        'wrapper-cluster-task-surface',
      );
    },
  },
});
