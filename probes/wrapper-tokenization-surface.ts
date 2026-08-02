import { definePresence } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default definePresence({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'presence-wrapper-tokenization-surface',
    description: 'The wrapper baseline enumerates its complete owned tokenization surface and held decisions.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh tokenization-presence',
        'wrapper-tokenization-surface',
      );
    },
  },
});
