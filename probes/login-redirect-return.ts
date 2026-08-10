import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s) — the unit tier alone.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/auth-redirect.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-login-redirect-return-green',
      description:
        'A login redirect carries the requested path AND its query through sign-in and back, and refuses an off-origin returnTo.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'login-redirect-return');
      },
    },
    {
      name: 'mutation-login-redirect-return-caught',
      description: 'A guard that redirects to sign-in without a returnTo turns the redirect-return suite red.',
      kind: 'mutation',
      // MEASURED COLLATERAL (family: shared source read by the unit suite). This
      // sabotage edits a real src/ module, and bunfig.unit.toml roots the suite at
      // tests/unit where 16 of 20 files import ../../src/**, so the whole unit run
      // reddens. On the 6f5907a matrix this row broke with control_failed naming
      // diene/bun-base#bun-unit-tests, control output "task: [unit:default] bun test"
      // - the control RAN and FAILED, so the blame was correct, and the empty array
      // here was a positive assertion of no collateral that got believed.
      expectedImpact: ['bun-unit-tests'],
      async run(repo: any) {
        // The round trip is library code; the loss happens at the CALL SITE, and a
        // call with the login path alone typechecks. Every protected deep link
        // would then land on the home page after sign-in.
        const path = 'src/adapters/auth/guard.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            "buildLoginRedirect('/api/logto/sign-in', returnTo)",
            "buildLoginRedirect('/api/logto/sign-in')",
          ),
        );
        await expectBunRed(repo, command, 'login-redirect-return');
      },
    },
  ],
};
