import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-lpsm-labels-green',
    description: 'Every wrapper object carries the complete stacked service-tree projection and prefix override.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh labels', 'wrapper-lpsm-labels');
    },
  },
  mutation: {
    name: 'mutation-wrapper-lpsm-labels-caught',
    description: 'Dropping a required service-tree key makes conformance red.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/values.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, { find: '  module: api\n', replace: '' });
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh labels', 'wrapper-lpsm-labels');
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
