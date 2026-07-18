import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-lpsm-hostnames-green',
    description:
      'Generic ordinary/instance dotted derivation, inverse parsing, normalization, and collision checks pass.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh lpsm', 'wrapper-lpsm-hostnames');
    },
  },
});
