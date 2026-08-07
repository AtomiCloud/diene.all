import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-non-trusted-action-pins-green',
      description: 'Every authored non-trusted action uses an exact SHA plus tag comment.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c dlint action-pins non-trusted', 'non-trusted-action-pins');
      },
    },
    {
      name: 'mutation-non-trusted-action-pins-caught',
      description: 'A focused sabotage must turn the non-trusted-action-pins mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        await repo.patch('.github/workflows/🛡️merge-gatekeeper.yml', {
          find: 'upsidr/merge-gatekeeper@09af7a82c1666d0e64d2bd8c01797a0bcfd3bb5d # v1.2.1',
          replace: 'upsidr/merge-gatekeeper@v1.2.1',
        });
        await expectRed(repo, 'nix develop .#ci -c dlint action-pins non-trusted', 'non-trusted-action-pins');
      },
    },
  ],
};
