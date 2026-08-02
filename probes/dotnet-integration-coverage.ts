import { expectGreen, expectRed } from './lib/helpers.ts';
import { discoverDotnetProject } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-integration-coverage-green',
      description: 'The merged integration ledger contains only App* sources at or above 80%.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:int:coverage', 'dotnet-integration-coverage', 600000);
      },
    },
    {
      name: 'mutation-dotnet-integration-coverage-caught',
      description: 'One uncovered App member with real sequence points turns the threshold red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-deadcode-all', 'dotnet-deadcode-production'],
      async run(repo: any) {
        const application = await discoverDotnetProject(repo, 'App*/*.csproj');
        const lines = Array.from({ length: 40 }, (_, index) => `        total += ${index + 1};`).join('\n');
        await repo.write(
          `${application.directory}/CoverageGap.cs`,
          `namespace ${application.rootNamespace};\n\npublic class CoverageGap\n{\n    public int Uncovered()\n    {\n        var total = 0;\n${lines}\n        return total;\n    }\n}\n`,
        );
        await expectRed(
          repo,
          'nix develop .#ci -c pls test:int:coverage',
          'dotnet-integration-coverage',
          600000,
          'int tests or merged coverage failed',
        );
      },
    },
  ],
};
