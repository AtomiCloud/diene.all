import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';
import { packPackages } from './lib/dotnet-package.ts';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-package-metadata-green',
    description: 'Both nupkgs carry the required identity, README, icon, license, repository, and skill metadata.',
    async run(repo: any) {
      await packPackages(repo, 'dotnet-lib-package-metadata-pack');
      await expectGreen(
        repo,
        'nix develop .#ci -c ./scripts/validate/dotnet-package.sh metadata',
        'dotnet-lib-package-metadata',
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-package-metadata-caught',
    description: 'Removing PackageReadmeFile from one packable project turns metadata validation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('Lib/Lib.csproj', {
        find: '    <PackageReadmeFile>README.md</PackageReadmeFile>\n',
        replace: '',
      });
      await packPackages(repo, 'dotnet-lib-package-metadata-mutation-pack');
      await expectRed(
        repo,
        'nix develop .#ci -c ./scripts/validate/dotnet-package.sh metadata',
        'dotnet-lib-package-metadata',
      );
    },
  },
});
