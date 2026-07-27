import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-helm-lint-green',
      description: 'Helm lint accepts the root chart through its direct invocation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c helm lint infra/root_chart', 'helm-lint');
      },
    },
    {
      name: 'mutation-helm-lint-caught',
      description: "A schema-invalid value supplied through Helm's real CLI override seam turns direct lint red.",
      kind: 'mutation',
      async run(repo: any) {
        await expectRed(
          repo,
          'nix develop .#ci -c helm lint infra/root_chart --set worker.replicas=invalid',
          'helm-lint',
        );
      },
    },
  ],
};
