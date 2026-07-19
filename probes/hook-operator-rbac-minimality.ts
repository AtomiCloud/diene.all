import { expectGreen, expectRed } from './lib/helpers.ts';

const cmd = 'nix develop .#ci -c pre-commit run a-operator-rbac --all-files';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-operator-rbac-minimality-green',
      description: 'The RBAC hook passes: no wildcard grants and the committed Role matches the markers.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, cmd, 'hook-operator-rbac-minimality');
      },
    },
    {
      name: 'mutation-hook-operator-rbac-minimality-caught',
      description: 'Adding a wildcard RBAC marker must redden the RBAC hook.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('adapters/operator/controllers/note_controller.go', {
          find: '// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch',
          replace:
            '// +kubebuilder:rbac:groups="",resources=events,verbs=create;patch\n// +kubebuilder:rbac:groups="*",resources="*",verbs="*"',
        });
        await expectRed(repo, cmd, 'hook-operator-rbac-minimality');
      },
    },
  ],
};
