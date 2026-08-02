import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { breakAdapter } from './lib/go.ts';

const gate = 'nix develop .#ci -c pls test:int';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-integration-tests-green',
      description: 'Adapter tests pass against a real testcontainers dependency.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'integration-tests');
      },
    },
    {
      name: 'mutation-integration-tests-caught',
      description: 'Breaking an adapter write must turn the integration tier red.',
      kind: 'mutation',
      // The write lands under a different key, so the read-back misses entirely
      // and the tier fails on the Load error rather than on a value mismatch.
      // The adapter is tracked and reverted to HEAD once this row's assertion has
      // run, so every other row still meets a clean tree: no collateral.
      expectedImpact: [],
      async run(repo: any) {
        await breakAdapter(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'integration-tests', /Load\(\) error = redis: nil/);
        } finally {
          await restoreProbeState(repo, ['adapters']);
        }
      },
    },
  ],
};
