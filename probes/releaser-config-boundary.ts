import { expectGreen, expectRed } from './lib/helpers.ts';

// Composed, strictly non-publishing proof of the pre-2p release surface. `sg`
// exposes no safe dry-run that consumes the config, so per the RB-339 ruling this
// gate composes two halves and each proves a distinct boundary:
//   half A — the `releaser` executable and its `release` subcommand/`-c` option
//            exist in the real `.#releaser` shell (the RB-339 exit-127 cure);
//   half B — the repository's sanctioned release-config validator parses and
//            validates the real `atomi_release.yaml` (schema + D3 types).
// Neither half invokes a publication-capable path: half A is `--help` only, half B
// is pure yq/jq validation. The mutation corrupts the config so half B fails,
// proving the configuration boundary is load-bearing (invalid config → red).
const RELEASER_SURFACE =
  "nix develop --no-write-lock-file .#releaser -c bash -c 'command -v releaser >/dev/null && releaser release --help >/dev/null'";
const CONFIG_VALIDATOR =
  "nix develop --no-write-lock-file .#ci -c bash -c './scripts/validate/release-config.sh schema && ./scripts/validate/release-config.sh types'";
const COMPOSED = `${RELEASER_SURFACE} && ${CONFIG_VALIDATOR}`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-releaser-config-boundary-green',
      description:
        'The pre-2p releaser release surface resolves in .#releaser and the sanctioned validator consumes and accepts the real atomi_release.yaml — no publication-capable path is invoked.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, COMPOSED, 'releaser-config-boundary');
      },
    },
    {
      name: 'mutation-releaser-config-boundary-caught',
      description:
        'An invalid atomi_release.yaml must fail the config half of the composed check, proving the configuration boundary is exercised rather than help-only.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('atomi_release.yaml', { find: 'branches:\n  - main', replace: 'branches:\n  - develop' });
        await expectRed(repo, COMPOSED, 'releaser-config-boundary');
      },
    },
  ],
};
