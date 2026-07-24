import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const coverageCommand = (tier: 'unit' | 'int') => `nix develop .#ci -c pls test:${tier}:coverage`;

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-cobertura-artifact-scope-green',
    description: 'Cobertura XML packages are parsed and confined to the Lib*/App* tier ledgers.',
    async run(repo: any) {
      await expectGreen(repo, coverageCommand('unit'), 'dotnet-cobertura-artifact-scope-unit', 600000);
      await expectGreen(repo, coverageCommand('int'), 'dotnet-cobertura-artifact-scope-int', 600000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-cobertura-artifact-scope-escape-caught',
    description: 'An escaped App package injected into the unit Cobertura artifact makes the parser gate red.',
    expectedImpact: ['dotnet-unit-coverage', 'dotnet-integration-coverage'],
    async run(repo: any) {
      await repo.patch('scripts/local/dotnet-test.sh', {
        find: '[ ! -f "${report}" ] && echo "❌ No merged ${kind} coverage report produced" >&2 && exit 1',
        replace: `[ ! -f "${report}" ] && echo "❌ No merged ${kind} coverage report produced" >&2 && exit 1
xmlstarlet ed -L -s '/coverage/packages' -t elem -n package -v '' \\
  -i '/coverage/packages/package[last()]' -t attr -n name -v 'App.ScopeEscape' \\
  -i '/coverage/packages/package[last()]' -t attr -n line-rate -v '1' "\${report}"`,
      });
      await expectRed(repo, coverageCommand('unit'), 'dotnet-cobertura-artifact-scope', 600000);
    },
  },
});
