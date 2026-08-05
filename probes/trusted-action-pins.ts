import { expectGreen, expectRedBecause } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-trusted-action-pins-green',
      description: 'Every authored trusted action uses a major-version pin.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/action-pins.sh trusted', 'trusted-action-pins');
      },
    },
    {
      name: 'mutation-trusted-action-pins-caught',
      description: 'A focused sabotage must turn the trusted-action-pins mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/workflows/⚡reusable-precommit.yaml', {
          find: 'AtomiCloud/actions.setup-nix@v3',
          replace: 'AtomiCloud/actions.setup-nix@f366a9f3997acdf7f335445809fd85e3a157147f',
        });
        await expectRedBecause(
          repo,
          'nix develop .#ci -c ./scripts/validate/action-pins.sh trusted',
          'trusted-action-pins',
          [
            '.github/workflows/⚡reusable-precommit.yaml',
            "trusted action 'AtomiCloud/actions.setup-nix' must use a major pin",
          ],
        );
      },
    },
  ],
};
