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
    // The registry arms below cover the fault this repository actually shipped:
    // flake.nix floated on `nix-registry/v3` while flake.lock sat at v3.7.0, and
    // the moving tag had advanced to v3.12.0 underneath it without anything going
    // red. The old check string-matched the alias, so it could not have caught it.
    //
    // Each arm rewrites the atomipkgs pin to one specific unacceptable form. They
    // are separate probes rather than one loop because a single arm that fails
    // tells you WHICH form slipped through.
    ...(
      [
        {
          name: 'mutation-registry-moving-major-alias-caught',
          description: 'The moving `v3` major alias must turn the nixpkgs-pin mechanism red.',
          replacement: 'v3',
          why: 'the alias the repository actually floated on',
        },
        {
          name: 'mutation-registry-moving-minor-alias-caught',
          description: 'The moving `v3.12` minor alias must turn the nixpkgs-pin mechanism red.',
          replacement: 'v3.12',
          why: 'two-part tags move too - the registry retargets them at each patch',
        },
        {
          name: 'mutation-registry-unadopted-major-caught',
          description: 'A v4 series registry pin must turn the nixpkgs-pin mechanism red.',
          replacement: 'v4.0.0',
          why: 'exact, but a major this tree has not adopted',
        },
      ] as const
    ).map(arm => ({
      name: arm.name,
      description: arm.description,
      kind: 'mutation' as const,
      expectedImpact: [],
      async run(repo: any) {
        const flake = await repo.read('flake.nix');
        const mutated = flake.replace(
          /atomipkgs\.url = "github:AtomiCloud\/nix-registry\/v[0-9][^"]*";/,
          `atomipkgs.url = "github:AtomiCloud/nix-registry/${arm.replacement}";`,
        );
        if (mutated === flake) {
          throw new Error(
            `${arm.name} did not apply: no atomipkgs registry pin was found to rewrite to ` +
              `'${arm.replacement}' (${arm.why}). A mutation that changes nothing proves nothing, ` +
              'so this is a failure, not a skip.',
          );
        }
        await repo.write('flake.nix', mutated);
        await expectRed(repo, PIN, 'nixpkgs-pin');
      },
    })),
    {
      // The registry's own absence arm, and the one most worth having. A gate
      // built as `grep <good form> || fail` goes red on a deleted line for the
      // right reason, but a gate built as `if <line present> then check it` would
      // go VACUOUSLY GREEN here while asserting nothing at all. This arm is what
      // separates the two, so it must never be dropped as redundant.
      name: 'mutation-registry-pin-absence-caught',
      description: 'A flake with no atomipkgs input at all must go red, not vacuously green.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const flake = await repo.read('flake.nix');
        const stripped = flake
          .split('\n')
          .filter((line: string) => !/^\s*atomipkgs\.url\s*=/.test(line))
          .join('\n');
        if (stripped === flake) {
          throw new Error(
            'mutation-registry-pin-absence-caught did not apply: no atomipkgs input line was found to strip.',
          );
        }
        await repo.write('flake.nix', stripped);
        await expectRed(repo, PIN, 'nixpkgs-pin');
      },
    },
  ],
};
