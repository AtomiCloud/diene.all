import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-publish-workflow-wiring-green',
    description: 'Tag-triggered CD reaches the API-key publish entrypoint with caller-owned permissions.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/dotnet-lib-workflows.sh publish',
        'dotnet-lib-publish-workflow-wiring',
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-publish-workflow-wiring-caught',
    description: 'Pointing the publish job at a missing reusable workflow turns its wiring validator red.',
    expectedImpact: ['workflow-wiring'],
    async run(repo: any) {
      await repo.patch('.github/workflows/cd.yaml', {
        find: 'uses: ./.github/workflows/⚡reusable-publish.yaml',
        replace: 'uses: ./.github/workflows/⚡missing-publish.yaml',
      });
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/dotnet-lib-workflows.sh publish',
        'dotnet-lib-publish-workflow-wiring',
      );
    },
  },
});
