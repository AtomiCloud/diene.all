import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-rendered-manifests-green',
    description: 'Helm, kubeconform, and definition-only VAP evaluation accept the full stack.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh rendered-manifests',
        'wrapper-rendered-manifests',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-rendered-manifests-caught',
    description: 'The one wiring fault, an image tagged latest, is denied by the VAP stage.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('chart/values.yaml', { find: 'tag: 6.9.2 # @schema', replace: 'tag: latest # @schema' });
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh rendered-manifests',
        'wrapper-rendered-manifests',
      );
    },
  },
});
