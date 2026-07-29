import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description: 'The in-process SIT driver reaches the demo through its real ASP.NET pipeline.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Breaking the demo health contract turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-integration-coverage'],
      async run(repo: any) {
        await repo.patch('App/DemoEndpoint.cs', {
          find: 'new { Status = "ok" }',
          replace: 'new { Status = "probe" }',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
