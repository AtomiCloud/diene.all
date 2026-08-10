import { expectGreen, expectRedWithDiagnostic, restoreProbeState } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

const gate = 'nix develop .#ci -c task test:unit:coverage';

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
      description: 'A lib source the profile never measures must turn the unit ledger red.',
      kind: 'mutation',
      async run(repo: any) {
        // A statement-free declaration keeps the percentage at 100 and never reaches the profile, so only a derived source set sees it.
        const planted = await plantGoFile(repo, 'lib/**/*.go', 'probe_uncovered.go', 'type ProbeUncovered struct{}');
        try {
          await expectRedWithDiagnostic(repo, gate, 'unit-coverage-scope', /unit coverage is missing 'lib\/.*\.go'/);
        } finally {
          await restoreProbeState(repo, [planted]);
        }
      },
    },
  ],
};
