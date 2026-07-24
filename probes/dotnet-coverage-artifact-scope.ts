import { defineGate } from './lib/definition.ts';
import { addEscapingUnitProject } from './lib/dotnet.ts';

const COVERAGE_COMMAND = 'nix develop .#ci -c pls test:unit:coverage';
const REPORT = 'TestResults/unit/coverage/coverage.cobertura.xml';
const PARSE_MARKER = 'Parsed unit Cobertura package scope and per-package line rates';
const ESCAPE_MESSAGE = 'unit coverage escaped its [Lib*]* ledger: Escape';

async function output(repo: any, command: string, timeoutMs: number): Promise<{ code: number; text: string }> {
  const result = await repo.exec(command, { timeoutMs });
  return { code: result.exitCode, text: `${result.stdout}\n${result.stderr}` };
}

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-coverage-artifact-scope-green',
    description: 'The gate parses the merged unit Cobertura artifact and confines every package to [Lib*]* at 100%.',
    async run(repo: any) {
      const run = await output(repo, COVERAGE_COMMAND, 600000);
      if (run.code !== 0) {
        throw new Error(`dotnet-coverage-artifact-scope failed on the healthy repo: ${run.text}`);
      }
      if (!run.text.includes(PARSE_MARKER)) {
        throw new Error(`the coverage gate never parsed the Cobertura artifact: ${run.text}`);
      }

      const parsed = await output(
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
      if (!/^[0-9]+$/.test(valid ?? '') || Number(valid) <= 0) {
        throw new Error(`the merged unit Cobertura artifact measured no lines: ${parsed.text}`);
      }
      if (packages.length === 0) {
        throw new Error(`the merged unit Cobertura artifact declares no packages: ${parsed.text}`);
      }
      for (const entry of packages) {
        const [assembly, rate] = entry.split(' ');
        if (!/^Lib/.test(assembly ?? '')) {
          throw new Error(`the merged unit Cobertura artifact escaped its [Lib*]* ledger: ${assembly}`);
        }
        if (Number(rate) * 100 + 0.0000001 < 100) {
          throw new Error(`the merged unit Cobertura package ${assembly} reports line-rate ${rate}, below 100%`);
        }
      }
    },
  },
  mutation: {
    name: 'mutation-dotnet-coverage-artifact-scope-caught',
    description:
      'A fully covered package admitted into the unit ledger is rejected by the Cobertura package-scope parse.',
    expectedImpact: ['dotnet-unit-coverage', 'dotnet-multi-project-coverage'],
    async run(repo: any) {
      await addEscapingUnitProject(repo);
      const run = await output(repo, COVERAGE_COMMAND, 900000);
      if (run.code === 0) {
        throw new Error(`dotnet-coverage-artifact-scope stayed green after sabotage: ${run.text}`);
      }
      if (!run.text.includes(ESCAPE_MESSAGE)) {
        throw new Error(`the scope escape was not caught by the Cobertura package-scope parse: ${run.text}`);
      }
    },
  },
});
