import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

// The whole-repository deadcode component, invoked directly rather than through the composite dispatcher.
const gate = 'nix develop .#ci -c ./scripts/local/deadcode-whole.sh';

const deadDeclaration = 'func ProbeDead() int { return 1 }';
// The component reports findings as deadcode's own JSON, so the fixture is proven by its entry, not by a bare name match.
const deadFinding = /"Name": "ProbeDead",[\s\S]*?"File": "[^"]*probe_dead\.go"/;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-whole-green',
      description: 'Deadcode finds no unreachable function with test reachability included.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'deadcode-whole-repo');
      },
    },
    {
      name: 'mutation-deadcode-whole-caught',
      description: 'A dead exported function must turn the whole-repository deadcode component red.',
      kind: 'mutation',
      async run(repo: any) {
        const planted = await plantGoFile(repo, 'lib/**/*.go', 'probe_dead.go', deadDeclaration);
        try {
          await expectRedWithDiagnostic(repo, gate, 'deadcode-whole-repo', deadFinding);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
