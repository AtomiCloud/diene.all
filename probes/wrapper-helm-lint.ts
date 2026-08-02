import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed, withCleanProbeState } from './lib/helpers.ts';

// The committed landscape overlay. The base lint never reads it, so a break
// planted here only turns lint red while the overlay is genuinely stacked on.
const OVERLAY = 'chart/values.example.yaml';
const COMMAND = 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh lint';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-helm-lint-green',
    description: 'Every committed wrapper values stack passes Helm lint.',
    async run(repo: any) {
      await expectGreen(repo, COMMAND, 'wrapper-helm-lint');
    },
  },
  mutation: {
    name: 'mutation-wrapper-helm-lint-caught',
    description: 'An invalid pull policy in the committed landscape overlay turns wrapper Helm lint red.',
    expectedImpact: [],
    async run(repo: any) {
      // Breaking a stacked overlay rather than the chart's own apiVersion keeps the
      // mutation inside the surface the gate exists to defend: lint must reject bad
      // values arriving through the overlays, not merely malformed chart metadata
      // that would fail every Helm command alike.
      await withCleanProbeState(repo, [OVERLAY], async () => {
        const original = await repo.read(OVERLAY);
        await repo.write(OVERLAY, `${original}\nworkload:\n  image:\n    pullPolicy: Sometimes\n`);
        await expectRed(repo, COMMAND, 'wrapper-helm-lint');
      });
    },
  },
});
