import { expectGreen, expectRed } from './lib/helpers.ts';

// Composed, strictly non-publishing proof of the pre-2p release surface. `sg`
// exposes no safe dry-run that consumes the config, so per the RB-339 ruling this
// gate composes three halves and each proves a distinct boundary:
//   half A — the `releaser` executable and its `release` subcommand/`-c` option
//            exist in the real `.#releaser` shell (the RB-339 first-defect cure);
//   half B — the repository's sanctioned release-config validator parses and
//            validates the real `atomi_release.yaml` (schema + D3 types);
//   half C — `node` and `npm` resolve inside `.#releaser`, so the pinned npm
//            runtime (release.sh `-i npm`) has its binaries (the second defect).
// Halves A and C run under `nix develop --ignore-environment` so the ambient
// ~/.nix-profile PATH cannot leak node/npm into the check — the tools must come
// from the releaser env group. Neither half invokes a publication-capable path:
// half A is `--help` only, half B is pure yq/jq validation, half C is
// `command -v`. The mutation drops `nodejs` from the releaser group so half C
// fails, proving node/npm presence is load-bearing. (The invalid-config negative
// for half B is separately guarded by the release-config-schema and
// release-type-vocabulary gates.)
const RELEASER_SURFACE =
  "nix develop --ignore-environment --no-write-lock-file .#releaser -c bash -c 'command -v releaser >/dev/null && releaser release --help >/dev/null && command -v node >/dev/null && command -v npm >/dev/null'";
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
        'In a pure .#releaser environment the releaser surface plus node/npm resolve, and the sanctioned validator consumes and accepts the real atomi_release.yaml — no publication-capable path is invoked.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, COMPOSED, 'releaser-config-boundary');
      },
    },
    {
      name: 'mutation-releaser-config-boundary-caught',
      description:
        'Dropping nodejs from the releaser env group must fail the node/npm half in the pure .#releaser environment, proving the release runtime no longer depends on the CI runner incidental yarn/pnpm.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('nix/env.nix', {
          find: '  releaser = [\n    nodejs\n    releaser\n  ];',
          replace: '  releaser = [\n    releaser\n  ];',
        });
        await expectRed(repo, COMPOSED, 'releaser-config-boundary');
      },
    },
  ],
};
