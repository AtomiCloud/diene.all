import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';
import { packPackages } from './lib/dotnet-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-symbol-package-green',
    description: 'Each snupkg independently contains a portable PDB and matching nuspec.',
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-symbol-package-pack');
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/dotnet-package.sh symbols',
        'dotnet-lib-symbol-package',
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-symbol-package-caught',
    description: 'Replacing one symbols package with its PDB-free nupkg turns symbol validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-symbol-package-mutation-pack');
      await repo.exec(
        'package="$(find artifacts/package -maxdepth 1 -name \'AtomiCloud.Diene.Result.TestHelper.*.nupkg\' -print -quit)"; symbols="${package%.nupkg}.snupkg"; cp "${package}" "${symbols}"',
      );
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/dotnet-package.sh symbols',
        'dotnet-lib-symbol-package',
      );
    },
  },
});
