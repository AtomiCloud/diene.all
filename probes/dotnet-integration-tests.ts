import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description: 'Every infra preset reaches a real Testcontainers dependency.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 900000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Changing the source-owned landscape overlay turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-integration-coverage', 'dotnet-dev', 'dotnet-run', 'dotnet-preview'],
      async run(repo: any) {
        await repo.patch('App/Config/settings.lapras.yaml', {
          find: '    port: 6381',
          replace: '    port: 6382',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 900000);
      },
    },
  ],
};
