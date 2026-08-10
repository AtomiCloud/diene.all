import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-package-workflow-wiring-green',
    description: 'CI reaches the reusable packed-package validation entrypoint.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-lib-workflows.sh package',
        'bun-lib-package-workflow-wiring',
      );
    },
  },
  mutation: {
    name: 'mutation-bun-lib-package-workflow-wiring-caught',
    description: 'Pointing the package job at a nonexistent reusable workflow turns wiring validation red.',
    expectedImpact: ['workflow-wiring'],
    async run(repo: any) {
      await repo.patch('.github/workflows/ci.yaml', {
        find: 'uses: ./.github/workflows/⚡reusable-package-validate.yaml',
        replace: 'uses: ./.github/workflows/⚡missing-package-validate.yaml',
      });
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-lib-workflows.sh package',
        'bun-lib-package-workflow-wiring',
      );
    },
  },
});
