import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-fmt-nixfmt-green',
      description: 'The treefmt nixfmt member passes on the untouched Nix modules.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix fmt --no-write-lock-file -- --ci --formatters nixfmt', 'fmt-nixfmt');
      },
    },
    {
      name: 'mutation-fmt-nixfmt-caught',
      description: 'A focused sabotage must turn the fmt-nixfmt mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('nix/env.nix', { find: '  dev = [', replace: '  dev=[' });
        await expectRed(repo, 'nix fmt --no-write-lock-file -- --ci --formatters nixfmt', 'fmt-nixfmt');
      },
    },
  ],
};
