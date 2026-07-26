import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-bun-lib-readme-tokenization-green',
    description: 'The README renders package identity, keywords source, and badge URLs from scaffold values.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/bun-package.sh readme',
        'bun-lib-readme-tokenization',
      );
    },
  },
});
