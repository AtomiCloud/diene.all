import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-testhelper-meta-ledger-green',
    description: 'The independent meta tier confines coverage to *.TestHelper assemblies at 100%.',
    async run(repo: any) {
      await expectGreen(
        repo,
        'nix develop .#ci -c pls test:meta:coverage',
        'dotnet-lib-testhelper-meta-ledger',
        600000,
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-testhelper-meta-ledger-caught',
    description: 'One uncovered public helper member turns the meta ledger red.',
    expectedImpact: ['dotnet-deadcode-all', 'dotnet-deadcode-production'],
    async run(repo: any) {
      await repo.write(
        'TestHelper/MetaCoverageGap.cs',
        'namespace AtomiCloud.Diene.Config.TestHelper;\n\npublic static class MetaCoverageGap\n{\n    public static int Uncovered() => 42;\n}\n',
      );
      await expectRed(repo, 'nix develop .#ci -c pls test:meta:coverage', 'dotnet-lib-testhelper-meta-ledger', 600000);
    },
  },
});
