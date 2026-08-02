import { expectGreen, expectRed } from './lib/helpers.ts';
import { discoverDotnetProject } from './lib/dotnet.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-deadcode-all-green',
      description: 'The strict all-project dn-inspect pass reports no dead code.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop .#ci -c ./scripts/local/dotnet-dead-code.sh --strict-all',
          'dotnet-deadcode-all',
          900000,
        );
      },
    },
    {
      name: 'mutation-dotnet-deadcode-all-caught',
      description: 'A dead test-project type turns the all-project pass red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const tests = await discoverDotnetProject(repo, 'UnitTest*/*.csproj');
        await repo.write(
          `${tests.directory}/DeadExport.cs`,
          `namespace ${tests.rootNamespace};\n\ninternal static class DeadExport\n{\n    public static int NeverUsed() => 42;\n}\n`,
        );
        await expectRed(
          repo,
          'nix develop .#ci -c ./scripts/local/dotnet-dead-code.sh --strict-all',
          'dotnet-deadcode-all',
          900000,
          'DeadExport',
        );
      },
    },
  ],
};
