import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: medium (<3min) — two integration slices, no browser.
//
// The picker journey has two halves and neither needs a browser: the DISCOVERY
// half (Doc B fetch through the baked allowlist, ping each landscape, confirm a
// reachable pick into the auth-engine handoff) runs against a local Doc B fixture,
// and the ADMISSION half (an existing-home session never sees the picker at all)
// is a branch of the SSR guard. A browser session fixture would add a real Logto
// dependency without proving anything these two do not.
const discovery =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.int.toml tests/integration/picker.test.ts'";
const admission =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.int.toml tests/integration/auth.test.ts -t requireSession'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-picker-journey-green',
      description:
        'Doc B is fetched from an allowlisted host, every landscape is pinged, a reachable pick becomes an auth-engine handoff, and a session that already carries a home claim is routed home instead of into the picker.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, discovery, 'picker-journey');
        await expectBunGreen(repo, admission, 'picker-journey');
      },
    },
    {
      name: 'mutation-picker-journey-caught',
      description:
        'A guard that ignores the home claim and always reports pre-onboarding turns the admission slice red.',
      kind: 'mutation',
      expectedImpact: ['auth-integration'],
      async run(repo: any) {
        // The picker is SIGN-UP ONLY. A guard that always reports pre-onboarding
        // sends established users back through landscape selection, where a second
        // pick would move their home — the most damaging thing this flow can do.
        const path = 'src/adapters/auth/guard.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            "const home = await checkHomeLandscape(claims).unwrapOr({ phase: 'pre-onboarding' } as const);",
            "const home = { phase: 'pre-onboarding' } as const;",
          ),
        );
        await expectBunRed(repo, admission, 'picker-journey');
      },
    },
  ],
};
