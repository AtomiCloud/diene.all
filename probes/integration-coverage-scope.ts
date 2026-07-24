import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-integration-coverage-scoped',
      description: 'The integration coverprofile contains only adapter packages at threshold.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/local/test.sh int true false',
          'integration-coverage-scope',
        );
      },
    },
    {
      name: 'mutation-integration-coverage-caught',
      description: 'A corrupted adapter scope marker must turn the integration ledger red.',
      kind: 'mutation',
      async run(repo: any) {
        await repo.patch('.config/go-base.coverage.yaml', {
          find: '    pathMarker: /adapters/',
          replace: '    pathMarker: /lib/',
        });
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/local/test.sh int true false',
          'integration-coverage-scope',
        );
      },
    },
  ],
};
