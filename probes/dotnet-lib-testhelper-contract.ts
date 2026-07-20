import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-testhelper-contract-green',
    description: 'Repository unit tests consume the TestHelper assertion contract.',
    async run(repo: any) {
      await expectGreen(repo, 'nix develop .#ci -c pls test:unit', 'dotnet-lib-testhelper-contract', 600000);
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-testhelper-contract-caught',
    description: 'Inverting the helper assertion makes the ordinary unit mechanism red.',
    expectedImpact: ['dotnet-lib-testhelper-meta-ledger'],
    async run(repo: any) {
      await repo.patch('TestHelper/Note/NoteAssertions.cs', {
        find: '        if (!string.Equals(actual, expected, StringComparison.Ordinal))',
        replace: '        if (string.Equals(actual, expected, StringComparison.Ordinal))',
      });
      await expectRed(repo, 'nix develop .#ci -c pls test:unit', 'dotnet-lib-testhelper-contract', 600000);
    },
  },
});
