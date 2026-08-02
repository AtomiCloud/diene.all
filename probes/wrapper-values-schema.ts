import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed, withCleanProbeState } from './lib/helpers.ts';

// The deepest committed overlay. The base and landscape renders never read it, so
// a break planted here is invisible unless the gate really stacks it last.
const OVERLAY = 'chart/values.lapras.yaml';
const COMMAND = 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh schema';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-values-schema-green',
    description: 'The generated schema accepts every committed stacked values path.',
    async run(repo: any) {
      await expectGreen(repo, COMMAND, 'wrapper-values-schema');
    },
  },
  mutation: {
    name: 'mutation-wrapper-values-schema-caught',
    description:
      'An unsupported provider written into the committed cluster overlay is rejected by the gate command that stacks it.',
    expectedImpact: [],
    async run(repo: any) {
      // Sabotaging a committed overlay — rather than linting a throwaway file the
      // gate never reads — is what makes this a proof about the gate: it stays red
      // only while the schema command still validates the fully stacked values.
      await withCleanProbeState(repo, [OVERLAY], async () => {
        const original = await repo.read(OVERLAY);
        await repo.write(OVERLAY, `${original}\ngateway:\n  provider: unsupported\n`);
        await expectRed(repo, COMMAND, 'wrapper-values-schema');
      });
    },
  },
});
