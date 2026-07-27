import { expectGreen, expectRed } from './lib/helpers.ts';
import { plantGoFile } from './lib/go.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deadcode-whole-green',
      description: 'Deadcode and staticcheck find no unreachable code with tests included.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/local/deadcode.sh whole', 'deadcode-whole-repo');
      },
    },
    {
      name: 'mutation-deadcode-whole-caught',
      description: 'A dead exported function must turn the whole-repository pass red.',
      kind: 'mutation',
      expectedImpact: ['deadcode-production', 'unit-coverage-scope', 'go-lib-export-docs'],
      async run(repo: any) {
        await plantGoFile(repo, 'lib/**/*.go', 'probe_dead.go', 'func ProbeDead() int { return 1 }');
        await expectRed(repo, 'nix develop .#ci -c ./scripts/local/deadcode.sh whole', 'deadcode-whole-repo');
      },
    },
  ],
};
