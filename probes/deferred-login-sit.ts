import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: medium (<3min) — the integration tier against a local handoff fixture.
//
// The REAL deferred-login SIT needs a live dotnet-api to hand off to, which no
// probe sandbox has. What this row proves instead is the template's whole half of
// the contract: the initiate route's fail-closed posture, the nonce and iOS
// clipboard carrier it returns for an authenticated session, and its refusal to
// guess a host when no handoff backend is configured. The cross-service leg is
// verified in the shared SIT environment, not here.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.int.toml tests/integration/handoff.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deferred-login-sit-green',
      description:
        'Handoff initiation refuses an unauthenticated caller before it reaches the handoff host, returns the nonce and iOS clipboard carrier for a real session, and reports rather than guesses when no backend is configured.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'deferred-login-sit');
      },
    },
    {
      name: 'mutation-deferred-login-sit-caught',
      description: 'An initiate route that skips its unauthenticated check turns the fail-closed assertion red.',
      kind: 'mutation',
      expectedImpact: ['auth-integration'],
      async run(repo: any) {
        // A handoff nonce minted for an anonymous caller is a login token handed to
        // whoever asked. Nothing errors — the endpoint simply becomes an oracle.
        const path = 'src/app/api/handoff/initiate/route.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace("if (tokens[0] === 'err' || tokens[1].__kind === 'unauthed') {", 'if (false) {'),
        );
        await expectBunRed(repo, command, 'deferred-login-sit');
      },
    },
  ],
};
