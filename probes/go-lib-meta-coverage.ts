import { defineGate } from './lib/definition.ts';
import { addUncoveredTestHelper } from './lib/go-library.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/local/test.sh meta true false';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-meta-coverage-green',
    description: 'The active meta ledger covers only TestHelper packages at 100%.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-meta-coverage');
    },
  },
  mutation: {
    name: 'mutation-go-lib-meta-coverage-caught',
    description: 'Adding uncovered TestHelper code turns the scoped meta ledger red.',
    expectedImpact: [],
    async run(repo: any) {
      await addUncoveredTestHelper(repo);
      await expectRed(repo, gate, 'go-lib-meta-coverage');
    },
  },
});
