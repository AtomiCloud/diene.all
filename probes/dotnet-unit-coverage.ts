import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-unit-coverage-green',
      description: 'The merged unit ledger contains only Lib* sources at 100%.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pls test:unit:coverage', 'dotnet-unit-coverage', 600000);
      },
    },
    {
      name: 'mutation-dotnet-unit-coverage-caught',
      description: 'One uncovered Lib member turns the merged unit threshold red.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-coverage-artifact-scope',
        'dotnet-multi-project-coverage',
        'dotnet-deadcode-all',
        'dotnet-deadcode-production',
      ],
      async run(repo: any) {
        await repo.write(
          'Lib/CoverageGap.cs',
          'namespace AtomiCloud.DotnetBase.Lib;\n\npublic class CoverageGap\n{\n    public int Uncovered() => 42;\n}\n',
        );
        await expectRed(repo, 'nix develop .#ci -c pls test:unit:coverage', 'dotnet-unit-coverage', 600000);
      },
    },
  ],
};
