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
    description: 'Pinning one upstream service-tree key to the default prefix makes conformance red.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/values.yaml';
      const original = await repo.read(path);
      try {
        // Freeze exactly one upstream label key at the default prefix. This is the
        // shape the defect actually had: every default-prefix render stays
        // byte-identical, so only the prefix-override renders can catch it, and
        // only if they hold the upstream dependency's objects to the same
        // per-resource truth as the wrapper's own. A gate that skipped an upstream
        // object, or defaulted its missing slots to the expected value, stays green
        // here — which is why this sabotage, not a missing service-tree key, is what
        // proves dynamic upstream prefix propagation is load-bearing.
        await repo.patch(path, {
          find: "    labels:\n      '{{ .Values.global.labelPrefix }}/platform': sample\n",
          replace: '    labels:\n      atomi.cloud/platform: sample\n',
        });
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh labels', 'wrapper-lpsm-labels');
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
