import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-hook-helm-lint-green',
    description: 'The wrapper-specific Helm lint hook passes.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c pre-commit run a-wrapper-helm-lint --all-files',
        'wrapper-hook-helm-lint',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-hook-helm-lint-caught',
    description: 'Invalid wrapper chart metadata turns the hook red.',
    expectedImpact: ['wrapper-helm-lint'],
    async run(repo: any) {
      const path = 'chart/Chart.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, { find: 'apiVersion: v2', replace: 'apiVersion: invalid' });
        await expectRed(
          repo,
          'nix develop .#ci -c pre-commit run a-wrapper-helm-lint --all-files',
          'wrapper-hook-helm-lint',
        );
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
