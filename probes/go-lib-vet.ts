import { defineGate } from './lib/definition.ts';
import { plantVetMisuse } from './lib/go-library.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const gate = 'nix develop .#ci -c ./scripts/validate/go-vet.sh';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-go-lib-vet-green',
    description: 'Go vet validates the module through its own entrypoint.',
    async run(repo: any) {
      await expectGreen(repo, gate, 'go-lib-vet');
    },
  },
  mutation: {
    name: 'mutation-go-lib-vet-caught',
    description: 'A printf format misuse turns the dedicated vet gate red.',
    expectedImpact: [],
    async run(repo: any) {
      await plantVetMisuse(repo);
      await expectRed(repo, gate, 'go-lib-vet');
    },
  },
});
