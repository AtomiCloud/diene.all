import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-helm-lint-green',
      description: 'The generated Helm lint hook passes the root chart.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-helm-lint --all-files', 'hook-helm-lint');
      },
    },
    {
      name: 'mutation-hook-helm-lint-caught',
      description: 'A schema-invalid value wired through the generated Helm hook turns that hook red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('nix/pre-commit.nix', {
          find: 'entry = "${packages.kubernetes-helm}/bin/helm lint infra/root_chart";',
          replace:
            'entry = "${packages.kubernetes-helm}/bin/helm lint infra/root_chart --set worker.replicas=invalid";',
        });
        await expectRed(repo, 'nix develop .#ci -c pre-commit run a-helm-lint --all-files', 'hook-helm-lint');
      },
    },
  ],
};
