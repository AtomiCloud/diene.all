import { defineGate } from './lib/definition.ts';
import { flipMetaAssertion } from './lib/go-library.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/local/test.sh meta false false';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-meta-tests-green',
    description: 'The conditional TestHelper meta tier passes through its own task path.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-meta-tests');
    },
  },
  mutation: {
    name: 'mutation-go-lib-meta-tests-caught',
    description: 'Flipping one TestHelper contract assertion turns the meta tier red.',
    expectedImpact: [],
    async run(repo: any) {
      await flipMetaAssertion(repo);
      await expectRed(repo, gate, 'go-lib-meta-tests');
    },
  },
});
