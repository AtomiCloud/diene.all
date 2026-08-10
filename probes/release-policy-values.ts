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
        // Schema v2: the title moved from the changelog plugin's changelogTitle
        // to release.changelog.title, and the file from atomi_release.yaml to
        // release.yaml. The sabotage is unchanged in kind — drift the declared
        // title away from the changelog's own opening bytes.
        await repo.patch('release.yaml', {
          find: '    title: |-\n      # Changelog',
          replace: '    title: |-\n      # Broken Changelog',
        });
        await expectRed(repo, VALIDATOR, 'release-policy-values');
      },
    },
  ],
};
