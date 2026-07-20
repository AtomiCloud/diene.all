import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-lib-workflows.sh publish';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-publish-workflow-wiring-green',
    description: 'CD reaches the publication guard and proxy verification path.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-publish-workflow-wiring');
    },
  },
  mutation: {
    name: 'mutation-go-lib-publish-workflow-wiring-caught',
    description: 'Pointing CD at a missing reusable workflow turns wiring validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('.github/workflows/cd.yaml', {
        find: './.github/workflows/reusable-go-publish.yaml',
        replace: './.github/workflows/⚡missing-go-publish.yaml',
      });
      await expectRed(repo, gate, 'go-lib-publish-workflow-wiring');
    },
  },
});
