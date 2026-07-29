import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-tests-green',
      description: 'The ASP.NET Core TestServer boundary renders registered and unknown typed problems.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-tests-caught',
      description: 'Changing a registered problem status turns the integration tier red.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-integration-coverage',
        'dotnet-deadcode-all',
        'dotnet-deadcode-production',
        'dotnet-dev',
        'dotnet-run',
        'dotnet-preview',
      ],
      async run(repo: any) {
        await repo.patch('App/ProblemApp.cs', {
          find: '.Add<NoteMissing>(404, false,',
          replace: '.Add<NoteMissing>(409, false,',
        });
        await expectRed(repo, 'nix develop .#ci -c pls test:int', 'dotnet-integration-tests', 600000);
      },
    },
  ],
};
