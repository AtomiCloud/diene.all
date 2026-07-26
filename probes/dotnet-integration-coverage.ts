import { expectGreen, expectRed } from './lib/helpers.ts';

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
        const lines = Array.from({ length: 40 }, (_, index) => `        total += ${index + 1};`).join('\n');
        await repo.write(
          'App/CoverageGap.cs',
          `namespace AtomiCloud.Diene.Problems.App;\n\npublic class CoverageGap\n{\n    public int Uncovered()\n    {\n        var total = 0;\n${lines}\n        return total;\n    }\n}\n`,
        );
        await expectRed(repo, 'nix develop .#ci -c pls test:int:coverage', 'dotnet-integration-coverage', 600000);
      },
    },
  ],
};
