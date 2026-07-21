import { expectGreen } from './lib/helpers.ts';

// Hermetic, offline, publish-impossible argv regression for the RB-339 second
// defect. Runs scripts/validate/releaser-runtime-argv.sh inside the real
// .#releaser shell: it builds a FAKE local semantic-release package and proves,
// with no token / release / push / tag / workflow / network, that
//   * the version-suffixed binary NAME `semantic-release@23.0.1` is not resolvable
//     (the cause of the yarn/pnpm `<pm> exec` failure on the CI runner);
//   * npm resolves the installed package SPEC offline to the bare bin (the fix);
//   * the bare `semantic-release` executable name runs.
// yarn/pnpm are absent from the offline shell (the fix makes npm the only
// runtime); the script logs that skip explicitly rather than capping silently.
export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-releaser-runtime-argv-green',
      description:
        'The hermetic argv regression: version-suffixed binary name is unresolvable while npm resolves the pinned package spec (and the bare name) offline — no publication-capable path is invoked.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(
          repo,
          'nix develop --no-write-lock-file .#releaser -c ./scripts/validate/releaser-runtime-argv.sh',
          'releaser-runtime-argv',
        );
      },
    },
  ],
};
