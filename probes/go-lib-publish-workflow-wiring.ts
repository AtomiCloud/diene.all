import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-lib-workflows.sh publish';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-publish-workflow-wiring-green',
    description:
      'CD reaches the publication guard and proxy verification path, while Semantic Release resolves through the pinned releaser/npm runtime.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-publish-workflow-wiring');
    },
  },
  mutation: {
    name: 'mutation-go-lib-publish-workflow-wiring-caught',
    description: 'Removing the pinned npm runtime from the release invocation turns wiring validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('scripts/ci/release.sh', {
        find: 'releaser release -c atomi_release.yaml -i npm',
        replace: 'releaser release -c atomi_release.yaml',
      });
      await expectRed(repo, gate, 'go-lib-publish-workflow-wiring');
    },
  },
});
