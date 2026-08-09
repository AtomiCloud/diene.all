import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-hook-helm-docs-green',
    description: 'The wrapper-specific Helm docs hook finds no drift.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c pre-commit run a-wrapper-helm-docs --all-files',
        'wrapper-hook-helm-docs',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-hook-helm-docs-caught',
    description: 'Changing chart metadata without regenerating docs turns the hook red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('chart/Chart.yaml', {
        find: 'description: Minimal production-grade Helm wrapper template for AtomiCloud platform charts',
        replace: 'description: Drifted wrapper description',
      });
      await expectRed(
        repo,
        'nix develop .#ci -c pre-commit run a-wrapper-helm-docs --all-files',
        'wrapper-hook-helm-docs',
      );
    },
  },
});
