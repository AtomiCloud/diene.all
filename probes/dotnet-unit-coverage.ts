import { expectGreen, expectRed } from './lib/helpers.ts';
import { discoverDotnetProject } from './lib/dotnet.ts';

const COVERAGE_COMMAND = 'nix develop .#ci -c pls test:unit:coverage';
const REPORT = 'TestResults/unit/coverage/coverage.cobertura.xml';

async function run(repo: any, command: string, timeoutMs: number): Promise<{ code: number; text: string }> {
  const result = await repo.exec(command, { timeoutMs });
  return { code: result.exitCode, text: `${result.stdout}\n${result.stderr}` };
}

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-dotnet-unit-coverage-green',
      description:
        'The merged unit ledger contains only Lib* packages at 100% and emits a parseable Cobertura artifact.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, COVERAGE_COMMAND, 'dotnet-unit-coverage', 600000);
        const parsed = await run(
          repo,
          `nix develop .#ci -c xmlstarlet sel -t -v '/coverage/@lines-valid' -n -m '/coverage/packages/package' -v '@name' -o ' ' -v '@line-rate' -n ${REPORT}`,
          120000,
        );
        if (parsed.code !== 0) {
          throw new Error(`the merged unit Cobertura artifact is unreadable: ${parsed.text}`);
        }
        const [valid, ...packages] = parsed.text
          .split('\n')
          .map(line => line.trim())
          .filter(line => line.length > 0);
        if (!/^[0-9]+$/.test(valid ?? '') || Number(valid) <= 0 || packages.length === 0) {
          throw new Error(`the merged unit Cobertura artifact is empty: ${parsed.text}`);
        }
        for (const entry of packages) {
          const [assembly, rate] = entry.split(' ');
          if (!/^Lib/.test(assembly ?? '') || Number(rate) * 100 + 0.0000001 < 100) {
            throw new Error(`the merged unit Cobertura artifact escaped its 100% Lib* ledger: ${entry}`);
          }
        }
      },
    },
    {
      name: 'mutation-dotnet-unit-coverage-caught',
      description: 'One uncovered Lib member turns the merged unit threshold red.',
      kind: 'mutation',
      expectedImpact: ['dotnet-multi-project-coverage', 'dotnet-deadcode-all', 'dotnet-deadcode-production'],
      async run(repo: any) {
        const library = await discoverDotnetProject(repo, 'Lib*/*.csproj');
        await repo.write(
          `${library.directory}/CoverageGap.cs`,
          `namespace ${library.rootNamespace};\n\npublic class CoverageGap\n{\n    public int Uncovered() => 42;\n}\n`,
        );
        await expectRed(repo, COVERAGE_COMMAND, 'dotnet-unit-coverage', 600000, 'unit tests or merged coverage failed');
      },
    },
  ],
};
