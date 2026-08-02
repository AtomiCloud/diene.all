import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-fullname-green',
    description: 'Rendered names and dependency overrides use service plus one dash plus fused token.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh fullname', 'wrapper-fullname');
    },
  },
  mutation: {
    name: 'mutation-wrapper-fullname-caught',
    description: 'A multi-dash primary override is rejected.',
    expectedImpact: [],
    async run(repo: any) {
      const path = 'chart/values.yaml';
      const original = await repo.read(path);
      try {
        await repo.patch(path, {
          find: 'fullnameOverride: wrapper-api',
          replace: 'fullnameOverride: wrapper-main-cache',
        });
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh fullname', 'wrapper-fullname');
      } finally {
        await repo.write(path, original);
      }
    },
  },
});
