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
        await repo.patch('scripts/local/secrets.sh', {
          find: 'case "${action}" in',
          replace: 'case "${action}"    in',
        });
        await expectRedBecause(repo, 'nix fmt --no-write-lock-file -- --ci --formatters shfmt', 'fmt-shfmt', [
          'scripts/local/secrets.sh',
          'unexpected changes detected',
        ]);
      },
    },
  ],
};
