import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: medium (<3min) — the integration tier with a cookie-jar fixture and a local
// OIDC stand-in; no live Logto, no container.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.int.toml tests/integration/auth.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-auth-integration-green',
      description:
        'Server auth assembles from config, fails CLOSED to the unauthed wire state without a session cookie, and routes a session by its home claim.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'auth-integration');
      },
    },
    {
      name: 'mutation-auth-integration-caught',
      description: 'A session-cookie check that always reports a session turns the fail-closed assertion red.',
      kind: 'mutation',
      expectedImpact: ['deferred-login-sit'],
      async run(repo: any) {
        // Failing OPEN is the dangerous direction: every anonymous request would be
        // treated as having a session and would proceed until some downstream call
        // failed for an unrelated-looking reason.
        const path = 'src/adapters/auth/session.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace("(jar.get(SESSION_COOKIE)?.value ?? '') !== '';", 'true;'));
        await expectBunRed(repo, command, 'auth-integration');
      },
    },
  ],
};
