import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantProductionOnlySymbol } from './lib/go.ts';

// Keep the production-only pass independent from the composite `pls deadcode` task.
const gate = 'nix develop .#ci -c ./scripts/local/deadcode.sh production';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-production-green',
      description: 'Production-only deadcode and staticcheck pass without test reachability.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'deadcode-production');
      },
    },
    {
      name: 'mutation-deadcode-production-caught',
      description: 'A symbol reachable only from a test must turn the production pass red.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantProductionOnlySymbol(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'deadcode-production', /ProbeProductionOnly/);
        } finally {
          await restoreProbeState(repo, planted);
        }
      },
    },
  ],
};
