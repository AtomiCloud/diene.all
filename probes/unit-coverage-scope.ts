import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

const gate = 'nix develop .#ci -c pls test:unit:coverage';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-unit-coverage-scoped',
      description: 'The unit coverprofile contains only lib packages at 100 percent.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, gate, 'unit-coverage-scope');
      },
    },
    {
      name: 'mutation-unit-coverage-caught',
      description: 'An uncovered public lib function must turn the unit ledger red.',
      kind: 'mutation',
      expectedImpact: ['deadcode-whole-repo', 'deadcode-production'],
      async run(repo: any) {
        const planted = await plantGoFile(
          repo,
          'lib/**/*.go',
          'probe_uncovered.go',
          'func ProbeUncovered() int { return 1 }',
        );
        try {
          await expectRedWithDiagnostic(repo, gate, 'unit-coverage-scope', /unit coverage .* is below/);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
