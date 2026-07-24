import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

const packAgainstPublishedBaseline =
  'rm -rf artifacts/api-candidate && mkdir -p artifacts/api-candidate && dotnet pack Lib/Lib.csproj -c Release --output artifacts/api-candidate';

export default defineGate({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-api-compatibility-green',
    description: 'PackageValidation accepts the unchanged public API against the published 1.0.0 package.',
    async run(repo: any) {
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c '${packAgainstPublishedBaseline}'`,
        'dotnet-lib-api-compatibility',
        600000,
      );
    },
  },
  mutation: {
    name: 'mutation-dotnet-lib-api-compatibility-caught',
    description: 'Removing one public 1.0 factory member turns PackageValidation red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('Lib/ResultFactory.cs', {
        find: '\n    public static Result<T, E> Ok<T, E>(T value) => new(value);',
        replace: '',
      });
      await expectRed(
        repo,
        `nix develop .#ci -c bash -c '${packAgainstPublishedBaseline}'`,
        'dotnet-lib-api-compatibility',
        600000,
      );
    },
  },
});
