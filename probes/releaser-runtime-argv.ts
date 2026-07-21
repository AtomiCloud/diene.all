import { expectGreen, expectRed } from './lib/helpers.ts';

// Hermetic, offline, publish-impossible argv regression for the RB-339 second
// defect. Runs scripts/validate/releaser-runtime-argv.sh inside the real
// .#releaser shell. It builds a FAKE local semantic-release package and proves,
// with no token / release / push / tag / workflow / network, that
//   * a REAL Yarn Classic `yarn exec semantic-release@23.0.1` fails nonzero and
//     never runs the package (the cause of the failed CI Release job), while the
//     same Yarn runs the bare `semantic-release` — isolating the `@23.0.1`
//     suffix as the sole cause;
//   * npm resolves the installed package SPEC offline to the bare bin (the fix);
//   * the bare `semantic-release` executable name runs.
//
// The real Yarn Classic is built OFFLINE from the pinned nixpkgs as the
// test-only `.#yarn-classic` package and injected into the fixture through
// RB339_YARN_CLASSIC_BIN. Yarn is deliberately NOT added to the `.#releaser`
// runtime — the script asserts yarn/pnpm are absent from that npm-only runtime
// and fails hard if the injected Yarn is missing (no silent skip). Every nix
// invocation on this path runs `--offline` (network unavailable).
const RUNTIME_ARGV_COMMAND =
  'RB339_YARN_CLASSIC_BIN="$(nix build --no-write-lock-file --offline --no-link --print-out-paths .#yarn-classic)/bin/yarn" ' +
  'nix develop --no-write-lock-file --offline .#releaser -c ./scripts/validate/releaser-runtime-argv.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-releaser-runtime-argv-green',
      description:
        'The hermetic argv regression: a real Yarn Classic `yarn exec semantic-release@23.0.1` fails without touching the sentinel while the same Yarn runs the bare binary, and npm resolves the pinned package spec (and the bare name) offline — no publication-capable path is invoked, and the Yarn is injected out-of-band so the release runtime stays npm-only.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, RUNTIME_ARGV_COMMAND, 'releaser-runtime-argv');
      },
    },
    {
      name: 'mutation-releaser-runtime-argv-suffix-dropped',
      description:
        'Dropping the exact `@23.0.1` suffix from the Yarn old-red makes the real Yarn resolve the bare `semantic-release` binary and run the sentinel; the regression must then turn red, so the exact version-suffixed Yarn execution is load-bearing (not a missing-binary artefact).',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('scripts/validate/releaser-runtime-argv.sh', {
          find: '"${RB339_YARN_CLASSIC_BIN}" exec \'semantic-release@23.0.1\'',
          replace: '"${RB339_YARN_CLASSIC_BIN}" exec \'semantic-release\'',
        });
        await expectRed(repo, RUNTIME_ARGV_COMMAND, 'releaser-runtime-argv');
      },
    },
  ],
};
