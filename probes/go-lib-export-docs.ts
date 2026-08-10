import { defineGate } from './lib/definition.ts';
import { removeExportDoc } from './lib/go-library.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-export-docs.sh';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-export-docs-green',
    description: 'Every exported Go symbol has a documentation comment.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-export-docs');
    },
  },
  mutation: {
    name: 'mutation-go-lib-export-docs-caught',
    description: 'Removing one export comment turns the documentation lint red.',
    expectedImpact: [],
    async run(repo: any) {
      await removeExportDoc(repo);
      await expectRed(repo, gate, 'go-lib-export-docs');
    },
  },
});
