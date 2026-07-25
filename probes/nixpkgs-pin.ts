import { expectGreen, expectRed } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-nixpkgs-pin-green',
      description: 'The flake, channel names, lock, and authoritative S1 snapshot agree.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#ci -c ./scripts/validate/nixpkgs-pin.sh', 'nixpkgs-pin');
      },
    },
    {
      name: 'mutation-nixpkgs-pin-caught',
      description: 'A focused sabotage must turn the nixpkgs-pin mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const snapshot = JSON.parse(await repo.read('nix/snapshots/nixpkgs.json'));
        snapshot.rev = '0000000000000000000000000000000000000000';
        await repo.write('nix/snapshots/nixpkgs.json', JSON.stringify(snapshot, null, 2) + '\n');
        await expectRed(repo, 'nix develop .#ci -c ./scripts/validate/nixpkgs-pin.sh', 'nixpkgs-pin');
      },
    },
  ],
};
