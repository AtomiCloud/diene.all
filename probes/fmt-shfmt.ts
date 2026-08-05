import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-fmt-shfmt-green',
      description: 'The treefmt shfmt member passes on tracked shell scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix fmt --no-write-lock-file -- --ci --formatters shfmt', 'fmt-shfmt');
      },
    },
    {
      name: 'mutation-fmt-shfmt-caught',
      description: 'A focused sabotage must turn the fmt-shfmt mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The sabotage is semantically identical shell - padding before a compound
        // command's terminating `;`, which shfmt removes under the treefmt member's
        // `-i 2 -s`. It lands in the surviving validator, which the workspace cannot lose
        // because each of its two release-policy modes has its own probe. Two earlier
        // subjects were chosen for a `case` block and then lost it, so this arm depends on
        // punctuation every non-trivial shell script has rather than on one keyword.
        await repo.patch('scripts/validate/workflows.sh', {
          find: 'if [ "${mode}" = "release-trigger" ]; then',
          replace: 'if [ "${mode}" = "release-trigger" ]  ; then',
        });
        await expectRedBecause(repo, 'nix fmt --no-write-lock-file -- --ci --formatters shfmt', 'fmt-shfmt', [
          'scripts/validate/workflows.sh',
          'unexpected changes detected',
        ]);
      },
    },
  ],
};
