import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-module-path.sh';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-module-path-green',
    description: 'The Go module path matches the configured mirror identity.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-module-path');
    },
  },
  mutation: {
    name: 'mutation-go-lib-module-path-caught',
    description: 'Changing only the declared module path turns identity validation red.',
    expectedImpact: [],
    async run(repo: any) {
      // Materialized libraries replace the template module identity, so derive
      // the current declaration instead of assuming diene.go-lib.
      const declared = (await repo.read('go.mod')).match(/^module\s+(\S+)$/m);
      if (!declared) throw new Error('go.mod declares no module path');
      await repo.patch('go.mod', {
        find: `module ${declared[1]}`,
        replace: 'module github.com/AtomiCloud/diene.go-wrong',
      });
      await expectRed(repo, gate, 'go-lib-module-path');
    },
  },
});
