import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

// Keep the whole-repository pass independent from the composite `pls deadcode` task.
const gate = 'nix develop .#ci -c ./scripts/local/deadcode.sh whole';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-whole-green',
      description: 'Deadcode and staticcheck find no unreachable code with tests included.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'deadcode-whole-repo');
      },
    },
    {
      name: 'mutation-deadcode-whole-caught',
      description: 'A dead exported function must turn the whole-repository pass red.',
      kind: 'mutation',
      expectedImpact: ['deadcode-production', 'unit-coverage-scope'],
      async run(repo: any) {
        const planted = await plantGoFile(repo, 'lib/**/*.go', 'probe_dead.go', 'func ProbeDead() int { return 1 }');
        try {
          await expectRedWithDiagnostic(repo, gate, 'deadcode-whole-repo', /ProbeDead/);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
