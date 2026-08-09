import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-wrapper-external-secret-green',
    description: 'Folder-level ExternalSecret rewrites produce collision-proof service and shared keys.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh secret',
        'wrapper-external-secret',
      );
    },
  },
  mutation: {
    name: 'mutation-wrapper-external-secret-caught',
    description: 'Changing the shared folder prefix is detected.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('chart/templates/externalsecret.yaml', {
        find: "target: 'SHARED_$1'",
        replace: "target: 'COLLIDE_$1'",
      });
      await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/helm-wrapper.sh secret', 'wrapper-external-secret');
    },
  },
});
