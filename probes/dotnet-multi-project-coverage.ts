import { addSecondUnitProject, discoverDotnetLayout, discoverDotnetProject } from './lib/dotnet.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const REPORT = 'TestResults/unit/coverage/coverage.cobertura.xml';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-multi-project-coverage-green',
      description: 'A registered Lib2 and UnitTest2 automatically join the merged unit ledger.',
      kind: 'baseline',
      async run(repo: any) {
        const layout = await discoverDotnetLayout(repo);
        const original = await discoverDotnetProject(repo, 'Lib*/*.csproj');
        const solution = await repo.read(layout.solution);
        const testConfig = await repo.read(layout.testConfig);
        try {
          await addSecondUnitProject(repo, false);
          await expectGreen(
            repo,
            'nix develop .#ci -c pls test:unit:coverage',
            'dotnet-multi-project-coverage',
            600000,
          );
          const merged = await repo.exec(
            `nix develop .#ci -c xmlstarlet sel -t -m '/coverage/packages/package' -v '@name' -n ${REPORT}`,
            { timeoutMs: 120000 },
          );
          const assemblies = `${merged.stdout}\n${merged.stderr}`
            .split('\n')
            .map((name: string) => name.trim())
            .filter((name: string) => name.length > 0);
          if (merged.exitCode !== 0 || !assemblies.includes(original.assemblyName) || !assemblies.includes('Lib2')) {
            throw new Error(
              `the merged unit artifact did not contain both ${original.assemblyName} and Lib2: ${assemblies}`,
            );
          }
        } finally {
          await repo.write(layout.solution, solution);
          await repo.write(layout.testConfig, testConfig);
          await repo.exec('rm -rf Lib2 UnitTest2');
        }
      },
    },
    {
      name: 'mutation-dotnet-multi-project-coverage-caught',
      description: 'An uncovered original Lib member is still caught when a covered Lib2 runs last.',
      kind: 'mutation',
      expectedImpact: ['dotnet-unit-coverage', 'dotnet-deadcode-all', 'dotnet-deadcode-production'],
      async run(repo: any) {
        const original = await discoverDotnetProject(repo, 'Lib*/*.csproj');
        await addSecondUnitProject(repo, false);
        await repo.write(
          `${original.directory}/CoverageGap.cs`,
          `namespace ${original.rootNamespace};\n\npublic class CoverageGap\n{\n    public int Uncovered() => 42;\n}\n`,
        );
        await expectRed(
          repo,
          'nix develop .#ci -c pls test:unit:coverage',
          'dotnet-multi-project-coverage',
          600000,
          'unit tests or merged coverage failed',
        );
      },
    },
  ],
};
