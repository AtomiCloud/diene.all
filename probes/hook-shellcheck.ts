import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-shellcheck-green',
      description: 'The generated shellcheck hook passes on the untouched scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-shellcheck --all-files', 'hook-shellcheck');
      },
    },
    {
      name: 'mutation-hook-shellcheck-caught',
      description: 'A focused sabotage must turn the hook-shellcheck mechanism red.',
      kind: 'mutation',
      expectedImpact: ['release-policy-values'],
      async run(repo: any) {
        const path = 'scripts/release/bump.sh';
        const source = await repo.read(path);
        try {
          await repo.write(path, `${source}\necho $UNQUOTED\n`);
          await expectRed(repo, 'nix develop .#ci -c pre-commit run a-shellcheck --all-files', 'hook-shellcheck');
        } finally {
          await repo.write(path, source);
        }
      },
    },
  ],
};
