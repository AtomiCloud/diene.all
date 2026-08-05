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
        // The subject was `scripts/local/secrets.sh` until that script was reduced to an
        // ensure-login helper with no `case` block. The sabotage is character-identical -
        // padding before a `case` keyword's `in`, which shfmt normalizes - and now lands in
        // a script the workspace cannot lose.
        await repo.patch('scripts/local/skills-sync.sh', {
          find: 'case "${status}" in',
          replace: 'case "${status}"    in',
        });
        await expectRedBecause(repo, 'nix fmt --no-write-lock-file -- --ci --formatters shfmt', 'fmt-shfmt', [
          'scripts/local/skills-sync.sh',
          'unexpected changes detected',
        ]);
      },
    },
  ],
};
