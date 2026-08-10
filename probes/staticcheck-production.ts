import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

// The production staticcheck component, invoked directly rather than through the composite dispatcher.
const gate = 'nix develop .#ci -c ./scripts/local/staticcheck-production.sh';

// Deadcode only tracks functions, so an unused unexported type can only be reported by staticcheck.
const unusedType = 'type probeStaticcheckProduction struct{}';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-staticcheck-production-green',
      description: 'Staticcheck finds no violation in the healthy repository with test analysis disabled.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'staticcheck-production');
      },
    },
    {
      name: 'mutation-staticcheck-production-caught',
      description: 'An unused unexported type must turn the production staticcheck component red.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantGoFile(repo, 'lib/**/*.go', 'probe_staticcheck_production.go', unusedType);
        try {
          await expectRedWithDiagnostic(
            repo,
            gate,
            'staticcheck-production',
            /probe_staticcheck_production\.go:\d+:\d+: type probeStaticcheckProduction is unused \(U1000\)/,
          );
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
