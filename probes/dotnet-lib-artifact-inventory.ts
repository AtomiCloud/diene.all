import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';
import { packPackages } from './lib/dotnet-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-artifact-inventory-green',
    description: 'Both lockstep packages and both symbol packages exist at the committed version.',
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-artifact-inventory-pack');
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/dotnet-package.sh inventory',
        'dotnet-lib-artifact-inventory',
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-artifact-inventory-caught',
    description: 'Omitting exactly one required symbols artifact turns inventory validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-artifact-inventory-mutation-pack');
      await repo.exec(
        'rm "$(find artifacts/package -maxdepth 1 -name \'AtomiCloud.Diene.ServerEngine.TestHelper.*.snupkg\' -print -quit)"',
      );
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/dotnet-package.sh inventory',
        'dotnet-lib-artifact-inventory',
      );
    },
  },
});
