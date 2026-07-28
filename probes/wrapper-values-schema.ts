import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-values-schema-green',
    description: 'The generated schema accepts every committed stacked values path.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh schema', 'wrapper-values-schema');
    },
  },
  mutation: {
    name: 'mutation-wrapper-values-schema-caught',
    description: 'An unsupported provider value is rejected by the generated schema.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.write('chart/values.probe-invalid.yaml', 'gateway:\n  provider: unsupported\n');
      await expectRed(
        repo,
        'nix develop .#ci -c helm lint chart --values chart/values.probe-invalid.yaml',
        'wrapper-values-schema',
      );
    },
  },
});
