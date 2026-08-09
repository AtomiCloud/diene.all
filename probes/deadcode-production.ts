import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantProductionOnlySymbol } from './lib/go.ts';

// The production deadcode component, invoked directly rather than through the composite dispatcher.
const gate = 'nix develop .#ci -c ./scripts/local/deadcode-production.sh';

// The component reports findings as deadcode's own JSON, so the fixture is proven by its entry, not by a bare name match.
const productionOnlyFinding = /"Name": "ProbeProductionOnly",[\s\S]*?"File": "[^"]*probe_production_only\.go"/;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-production-green',
      description: 'Deadcode finds no unreachable function without test reachability.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'deadcode-production');
      },
    },
    {
      name: 'mutation-deadcode-production-caught',
      description: 'A symbol reachable only from a test must turn the production deadcode component red.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantProductionOnlySymbol(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'deadcode-production', productionOnlyFinding);
        } finally {
          await restoreProbeState(repo, planted);
        }
      },
    },
  ],
};
