import { expectGreen, expectRed } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-unit-coverage-scoped',
      description: 'The unit coverprofile contains only lib packages at 100 percent.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/test.sh unit true false', 'unit-coverage-scope');
      },
    },
    {
      name: 'mutation-unit-coverage-caught',
      description: 'An uncovered public lib function must turn the unit ledger red.',
      kind: 'mutation',
      expectedImpact: ['deadcode-whole-repo', 'deadcode-production', 'go-lib-export-docs'],
      async run(repo: any) {
        await plantGoFile(repo, 'lib/**/*.go', 'probe_uncovered.go', 'func ProbeUncovered() int { return 1 }');
        await expectRed(repo, 'nix develop .#ci -c ./scripts/local/test.sh unit true false', 'unit-coverage-scope');
      },
    },
  ],
};
