import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-fmt-prettier-green',
      description: 'The treefmt Prettier member passes on Markdown and YAML.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix fmt --no-write-lock-file -- --ci --formatters prettier', 'fmt-prettier');
      },
    },
    {
      name: 'mutation-fmt-prettier-caught',
      description: 'A focused sabotage must turn the fmt-prettier mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.prettierrc.yaml', { find: 'arrowParens: avoid', replace: 'arrowParens:    avoid' });
        await expectRed(repo, 'nix fmt --no-write-lock-file -- --ci --formatters prettier', 'fmt-prettier');
      },
    },
  ],
};
