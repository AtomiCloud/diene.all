import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-publish-workflow-wiring-green',
    description: 'Tag-triggered CD reaches the reusable publish entrypoint.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-lib-workflows.sh publish',
        'bun-lib-publish-workflow-wiring',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-publish-workflow-wiring-caught',
    description: 'Pointing the publish job at a nonexistent reusable workflow turns wiring validation red.',
    expectedImpact: ['workflow-wiring'],
    async run(repo: any) {
      await repo.patch('.github/workflows/cd.yaml', {
        find: 'uses: ./.github/workflows/⚡reusable-publish.yaml',
        replace: 'uses: ./.github/workflows/⚡missing-publish.yaml',
      });
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-lib-workflows.sh publish',
        'bun-lib-publish-workflow-wiring',
      );
    },
  },
});
