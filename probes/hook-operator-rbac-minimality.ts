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
      description: 'Granting an overbroad destructive verb on the Note CR must redden the RBAC hook.',
      kind: 'mutation',
      async run(repo: any) {
        // Add a create grant on the primary Note CR — outside the least-privilege
        // allowlist (the reconciler only reads Notes).
        await repo.patch('infra/root_chart/templates/rbac/role.yaml', {
          find: '  - notes\n  verbs:\n  - get',
          replace: '  - notes\n  verbs:\n  - create\n  - get',
        });
        await expectRed(repo, cmd, 'hook-operator-rbac-minimality');
      },
    },
  ],
};
