import { defineGate } from './lib/definition.ts';
import { breakExample } from './lib/go-library.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-examples.sh';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-examples-green',
    description: 'Example functions compile and run as consumer-facing documentation.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-examples');
    },
  },
  mutation: {
    name: 'mutation-go-lib-examples-caught',
    description: 'Breaking one Example output turns the example gate red.',
    expectedImpact: [],
    async run(repo: any) {
      await breakExample(repo);
      await expectRed(repo, gate, 'go-lib-examples');
    },
  },
});
