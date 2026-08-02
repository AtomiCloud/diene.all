import { expectGreen, expectRed } from './lib/helpers.ts';
import { discoverDotnetProject } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  setup: {
    pre: ['find . -type d \\( -name bin -o -name obj \\) -prune -exec rm -rf -- {} + && rm -rf TestResults'],
  },
  probes: [
    {
      name: 'baseline-hook-dotnetlint-green',
      description: 'The generated dotnetlint hook accepts the healthy C# surface.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run dotnetlint --all-files', 'hook-dotnetlint', 600000);
      },
    },
    {
      name: 'mutation-hook-dotnetlint-caught',
      description: 'A suggestion-level unused import turns the dotnetlint hook red.',
      kind: 'mutation',
      expectedImpact: [
        'dotnet-unit-coverage',
        'dotnet-multi-project-coverage',
        'dotnet-deadcode-all',
        'dotnet-deadcode-production',
      ],
      async run(repo: any) {
        const library = await discoverDotnetProject(repo, 'Lib*/*.csproj');
        await repo.write(
          `${library.directory}/.editorconfig`,
          '[*.cs]\ndotnet_diagnostic.IDE0005.severity = suggestion\n',
        );
        await repo.write(
          `${library.directory}/LintViolation.cs`,
          `using System.Text;\n\nnamespace ${library.rootNamespace};\n\npublic static class LintViolation\n{\n    public static int Value => 1;\n}\n`,
        );
        await expectRed(
          repo,
          'nix develop .#ci -c pre-commit run dotnetlint --all-files',
          'hook-dotnetlint',
          600000,
          'IDE0005',
        );
      },
    },
  ],
};
