import { expectGreen, expectRed } from './lib/helpers.ts';
import { discoverDotnetLayout, discoverDotnetProject } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-analyzers-green',
      description: 'Release compilation with analyzers and warnings-as-errors is green.',
      kind: 'baseline',
      async run(repo: any) {
        const layout = await discoverDotnetLayout(repo);
        await expectGreen(
          repo,
          `nix develop .#ci -c dotnet build ${layout.solution} -c Release`,
          'dotnet-analyzers',
          600000,
        );
      },
    },
    {
      name: 'mutation-dotnet-analyzers-caught',
      description: 'A focused compiler type error is rejected by the enforcing build.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-unit-tests',
        'dotnet-integration-tests',
        'dotnet-unit-coverage',
        'dotnet-integration-coverage',
        'dotnet-multi-project-coverage',
        'dotnet-deadcode-all',
        'dotnet-deadcode-production',
        'dotnet-build',
        'dotnet-dev',
        'dotnet-run',
        'dotnet-preview',
      ],
      async run(repo: any) {
        const layout = await discoverDotnetLayout(repo);
        const library = await discoverDotnetProject(repo, 'Lib*/*.csproj');
        await repo.write(
          `${library.directory}/AnalyzerViolation.cs`,
          `namespace ${library.rootNamespace};\n\npublic static class AnalyzerViolation\n{\n    public static string Value => 42;\n}\n`,
        );
        await expectRed(
          repo,
          `nix develop .#ci -c dotnet build ${layout.solution} -c Release`,
          'dotnet-analyzers',
          600000,
          'CS0029',
        );
      },
    },
  ],
};
