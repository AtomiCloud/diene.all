import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantProductionOnlySymbol } from './lib/go.ts';

// The blocking hook is its own enforcement mechanism: registration, runtime and sequencing are only proven here.
const gate = 'nix develop .#ci -c pre-commit run a-deadcode --all-files';
const gateTimeoutMs = 600000;

// A test-only symbol clears the two staticcheck components and the whole-repository deadcode component, so the
// hook can only redden on its last strict component — which proves the hook ran the whole sequence.
const productionOnlyFinding = /"Name": "ProbeProductionOnly",[\s\S]*?"File": "[^"]*probe_production_only\.go"/;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-deadcode-strict-green',
      description: 'The blocking deadcode hook passes the healthy repository.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'hook-deadcode-strict', gateTimeoutMs);
      },
    },
    {
      name: 'mutation-hook-deadcode-strict-caught',
      description:
        'A test-only symbol must turn the hook red on its last strict component, after the earlier ones pass.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantProductionOnlySymbol(repo);
        try {
          await expectRedWithDiagnostic(repo, gate, 'hook-deadcode-strict', productionOnlyFinding, gateTimeoutMs);
        } finally {
          await restoreProbeState(repo, planted);
        }
      },
    },
  ],
};
