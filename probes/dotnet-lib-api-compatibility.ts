import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const prepareBaseline =
  'rm -rf artifacts/api-baseline artifacts/api-candidate && mkdir -p artifacts/api-baseline artifacts/api-candidate && dotnet pack Lib/Lib.csproj -c Release --output artifacts/api-baseline';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-api-compatibility-green',
    description: 'PackageValidation accepts the unchanged public API against a locally packed 1.0 baseline.',
    async run(repo: any) {
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c '${prepareBaseline} && dotnet pack Lib/Lib.csproj -c Release --output artifacts/api-candidate -p:Version=1.0.1 -p:PackageValidationBaselineVersion=1.0.0 -p:RestoreAdditionalProjectSources=$PWD/artifacts/api-baseline'`,
        'dotnet-lib-api-compatibility',
        600000,
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-api-compatibility-caught',
    description: 'Removing one public 1.0 interface member turns PackageValidation red.',
    expectedImpact: [],
    async run(repo: any) {
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c '${prepareBaseline}'`,
        'dotnet-lib-api-baseline-pack',
        600000,
      );
      await repo.patch('Lib/INoteRepository.cs', {
        find: '\n    Task<NotePrincipal?> Find(string id, CancellationToken cancellationToken = default);',
        replace: '',
      });
      await expectRed(
        repo,
        'nix develop .#ci -c dotnet pack Lib/Lib.csproj -c Release --output artifacts/api-candidate -p:Version=1.0.1 -p:PackageValidationBaselineVersion=1.0.0 -p:RestoreAdditionalProjectSources=$PWD/artifacts/api-baseline',
        'dotnet-lib-api-compatibility',
        600000,
      );
    },
  },
});
