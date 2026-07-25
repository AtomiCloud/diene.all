import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-hook-enforce-exec-green',
      description: 'The generated executable-bit hook passes tracked shell scripts.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c pre-commit run a-enforce-exec --all-files', 'hook-enforce-exec');
      },
    },
    {
      name: 'mutation-hook-enforce-exec-caught',
      description: 'A focused sabotage must turn the hook-enforce-exec mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.exec('chmod -x scripts/ci/release.sh');
        await expectRed(repo, 'nix develop .#ci -c pre-commit run a-enforce-exec --all-files', 'hook-enforce-exec');
      },
    },
  ],
};
