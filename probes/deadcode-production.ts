import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile, plantProductionOnlySymbol } from './lib/go.ts';

// Keep the production-only pass independent from the composite `pls deadcode` task.
const gate = 'nix develop .#ci -c ./scripts/local/deadcode.sh production';
// The blocking hook registration is a second enforcement mechanism for the same two invocations.
const hook = 'nix develop .#ci -c pre-commit run a-deadcode --all-files';
const hookTimeoutMs = 600000;

// Deadcode only tracks functions, so an unused unexported type can only be reported by staticcheck.
const unusedType = 'type probeStaticcheckProduction struct{}';
// The pass reports findings as deadcode's own JSON, so the fixture is proven by its entry, not by a bare name match.
const productionOnlyFinding = /"Name": "ProbeProductionOnly",[\s\S]*?"File": "[^"]*probe_production_only\.go"/;

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
      name: 'baseline-deadcode-production-hook-green',
      description: 'The blocking deadcode hook runs the production pass on the healthy repository.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, hook, 'deadcode-production-hook', hookTimeoutMs);
      },
    },
    {
      name: 'mutation-deadcode-production-caught',
      description: 'A symbol reachable only from a test must turn the production deadcode invocation red.',
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
    {
      name: 'mutation-staticcheck-production-caught',
      description: 'An unused unexported type must turn the production staticcheck invocation red.',
      kind: 'mutation',
      // Deadcode stays green on this fixture, so the red is the staticcheck invocation alone; the whole pass reports it too.
      expectedImpact: ['deadcode-whole-repo', 'hook-golangci-lint', 'binary-smoke'],
      async run(repo: any) {
        const planted = await plantGoFile(repo, 'lib/**/*.go', 'probe_staticcheck_production.go', unusedType);
        try {
          await expectRedWithDiagnostic(
            repo,
            gate,
            'deadcode-production',
            /probe_staticcheck_production\.go:\d+:\d+: type probeStaticcheckProduction is unused \(U1000\)/,
          );
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
    {
      name: 'mutation-deadcode-production-hook-caught',
      description: 'A test-only symbol must turn the blocking deadcode hook red once the whole pass clears it.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantProductionOnlySymbol(repo);
        try {
          await expectRedWithDiagnostic(repo, hook, 'deadcode-production-hook', productionOnlyFinding, hookTimeoutMs);
        } finally {
          await restoreProbeState(repo, planted);
        }
      },
    },
  ],
};
