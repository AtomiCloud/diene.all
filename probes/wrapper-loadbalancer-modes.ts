import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-loadbalancer-modes-green',
    description: 'AWS, OCI, and DigitalOcean LoadBalancer modes render the correct fixed-IP contract.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh lb',
        'wrapper-loadbalancer-modes',
      );
    },
  },
});
