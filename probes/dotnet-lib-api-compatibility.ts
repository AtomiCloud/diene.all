import { defineGate } from './lib/definition.ts';
import { expectGreen, expectRed } from './lib/helpers.ts';

// The 1.0.0 baseline package only exists after the library's own first release, so the
// baseline is conditioned off while 1.0.0 itself is being built. Pack a post-1.0.0 version
// to exercise the compatibility gate in the state that actually ships it.
const packAgainstPublishedBaseline =
  'rm -rf artifacts/api-candidate && mkdir -p artifacts/api-candidate && dotnet pack Lib/Lib.csproj -c Release -p:Version=1.0.1 --output artifacts/api-candidate';

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
    description: 'Removing one public 1.0 wire member turns the packaging gate red.',
    expectedImpact: [],
    async run(repo: any) {
      await repo.patch('Lib/SeamWire.cs', {
        find:
          '\n    /// <summary>Renders an instant as an RFC 3339 UTC timestamp.</summary>\n' +
          '    public static string Instant(DateTimeOffset value) =>\n' +
          '        value.ToUniversalTime().ToString(InstantFormat, CultureInfo.InvariantCulture);\n',
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
