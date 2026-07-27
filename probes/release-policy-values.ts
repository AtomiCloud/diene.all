import { expectGreen, expectRed } from './lib/helpers.ts';

// Gate: the real release-policy validator asserts the per-node changelogFile,
// changelogTitle prefix, and formatter-bearing prepareCmd values. The mechanism
// cascades; each descendant keeps its own local values and must satisfy it.
const VALIDATOR = 'nix develop .#ci --no-write-lock-file -c ./scripts/validate/release-policy.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-release-policy-values-green',
      description: 'the real release-policy validator accepts the node-local changelog and formatter values',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, VALIDATOR, 'release-policy-values');
      },
    },
    {
      name: 'mutation-release-policy-values-caught',
      description: 'the real validator rejects a changelogTitle that no longer matches the changelog bytes',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('atomi_release.yaml', {
          find: '      changelogTitle: |-\n        # Changelog',
          replace: '      changelogTitle: |-\n        # Broken Changelog',
        });
        await expectRed(repo, VALIDATOR, 'release-policy-values');
      },
    },
  ],
};
