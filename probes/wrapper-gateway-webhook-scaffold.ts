import { definePresence } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default definePresence({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'presence-wrapper-gateway-webhook-scaffold',
    description: 'The fixed health and internal webhook route contracts are documented and scaffolded.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh gateway-webhook-presence',
        'wrapper-gateway-webhook-scaffold',
      );
    },
  },
});
