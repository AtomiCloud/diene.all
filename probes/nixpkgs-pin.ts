import { expectGreen, expectRed } from './lib/helpers.ts';

const PIN = 'nix develop .#ci -c ./scripts/validate/nixpkgs-pin.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-nixpkgs-pin-green',
      description: 'Every nixpkgs input in flake.nix is pinned to an exact commit, and the lock agrees.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, PIN, 'nixpkgs-pin');
      },
    },
    {
      // The sabotage the gate exists for: someone swaps a commit pin back to a
      // channel name. That is not a typo, it is the exact regression the owner
      // ruled out - the branch moves upstream and the same tree builds
      // differently tomorrow, silently.
      name: 'mutation-nixpkgs-pin-caught',
      description: 'A nixpkgs input returned to a floating channel ref must turn the nixpkgs-pin mechanism red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const flake = await repo.read('flake.nix');
        const floated = flake.replace(
          /nixpkgs-unstable\.url = "github:NixOS\/nixpkgs\/[0-9a-f]{40}";/,
          'nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";',
        );
        if (floated === flake) {
          throw new Error(
            'mutation-nixpkgs-pin-caught did not apply: no commit-pinned nixpkgs-unstable input to float. ' +
              'A mutation that changes nothing proves nothing, so this is a failure, not a skip.',
          );
        }
        await repo.write('flake.nix', floated);
        await expectRed(repo, PIN, 'nixpkgs-pin');
      },
    },
    {
      // Second sabotage, aimed at the gate's own blind spot rather than at the
      // flake. The previous gate read a hand-maintained nix/snapshots/nixpkgs.json
      // and would pass on a repository whose flake it never opened. Deleting
      // every nixpkgs input must therefore read as a BROKEN gate, never as a
      // clean one - absence of a finding is not a finding of absence.
      name: 'mutation-nixpkgs-pin-absence-caught',
      description: 'A flake with no nixpkgs input at all must go red, not vacuously green.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const flake = await repo.read('flake.nix');
        const stripped = flake
          .split('\n')
          .filter((line: string) => !/^\s*nixpkgs[A-Za-z0-9_-]*\.url\s*=/.test(line))
          .join('\n');
        if (stripped === flake) {
          throw new Error(
            'mutation-nixpkgs-pin-absence-caught did not apply: no nixpkgs input lines were found to strip.',
          );
        }
        await repo.write('flake.nix', stripped);
        await expectRed(repo, PIN, 'nixpkgs-pin');
      },
    },
  ],
};
