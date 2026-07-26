import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description: 'The demo consumer resolves its real layered YAML files through the whole precedence order.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Changing the source-owned landscape overlay turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-integration-coverage', 'dotnet-dev', 'dotnet-run', 'dotnet-preview'],
      async run(repo: any) {
        await repo.patch('App/Config/settings.lapras.yaml', {
          find: '  host: docs.lapras.atomi.cloud',
          replace: '  host: docs.drifted.atomi.cloud',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
