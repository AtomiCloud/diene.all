import { defineGate } from './lib/definition.ts';
import { removeExportedSymbol } from './lib/go-library.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-api-compat.sh';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-api-compatibility-green',
    description: 'Gorelease accepts the current public surface against the sealed v1 baseline.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-api-compatibility');
    },
  },
  mutation: {
    name: 'mutation-go-lib-api-compatibility-caught',
    description: 'Renaming an exported function without a major version turns gorelease red.',
    expectedImpact: [],
    async run(repo: any) {
      await removeExportedSymbol(repo);
      await expectRed(repo, gate, 'go-lib-api-compatibility');
    },
  },
});
