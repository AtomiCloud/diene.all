import { defineSmoke } from './lib/definition.ts';
import { expectGreen } from './lib/helpers.ts';

// This library ships no TestHelper companion (dotnet-family usefulness lens: a
// pure value surface has no port to fake). The inherited meta machinery must
// therefore deactivate itself rather than red on an empty ledger, and it must
// leave no coverage artifact behind for CI to upload as an empty `meta` flag.
// The upstream gate this replaces (`dotnet-lib-testhelper-meta-ledger`) proves
// the ledger itself and lives on the template branch, where a TestHelper exists.
export default defineSmoke({
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  baseline: {
    name: 'baseline-dotnet-lib-meta-tier-inactive-green',
    description: 'With no TestHelper project the meta tier self-deactivates and produces no coverage artifact.',
    async run(repo: any) {
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c 'test -z "$(find . -maxdepth 2 -type f -path "*/TestHelper*.csproj" -print -quit)"'`,
        'dotnet-lib-meta-tier-inactive',
      );
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c 'pls test:meta:coverage | rg -Fq "meta tier is inactive"'`,
        'dotnet-lib-meta-tier-inactive',
        600000,
      );
      await expectGreen(
        repo,
        `nix develop .#ci -c bash -c 'test ! -e TestResults/meta/coverage/coverage.cobertura.xml'`,
        'dotnet-lib-meta-tier-inactive',
      );
    },
  },
});
