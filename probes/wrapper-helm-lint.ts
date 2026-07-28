import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-helm-lint-green',
    description: 'Every committed wrapper values stack passes Helm lint.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh lint', 'wrapper-helm-lint');
    },
  },
  mutation: {
    name: 'mutation-wrapper-helm-lint-caught',
    description: 'Invalid chart metadata turns wrapper Helm lint red.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/Chart.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, { find: 'apiVersion: v2', replace: 'apiVersion: invalid' });
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh lint', 'wrapper-helm-lint');
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
