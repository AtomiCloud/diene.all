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
      async run(repo: any) {
        const mutated = await breakAdapter(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'integration-tests', /Load\(\) error = redis: nil/);
        } finally {
          await restoreProbeState(repo, [mutated]);
        }
      },
    },
  ],
};
