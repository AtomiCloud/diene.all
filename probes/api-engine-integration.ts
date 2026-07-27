import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: medium (<3min) — the integration tier against a local Bun.serve backend
// fixture; no container, no network.
//
// This ONE row covers both the API-integration and the swagger/typed-adapter
// mechanisms from the matrix: the adapter under test is the generated api-engine
// binding surface, and a call through it is what proves the generated types, the
// backend resolution, and the Problem mapping at the same boundary. Splitting them
// would be two rows over one invoked mechanism.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.int.toml tests/integration/api-engine.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-api-engine-integration-green',
      description:
        'The api-engine resolves each configured backend with its LPSM coordinate and resource audience, and a real call round-trips through the typed client.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'api-engine-integration');
      },
    },
    {
      name: 'mutation-api-engine-integration-caught',
      description:
        'A binding whose resource name no longer matches the configured backend turns the integration suite red.',
      kind: 'mutation',
      expectedImpact: ['auth-integration'],
      async run(repo: any) {
        // The resource name IS the audience the access token is minted for. A wrong
        // one still builds a complete-looking binding and every authenticated call
        // fails at the backend with a 401 that looks like a login problem.
        const path = 'src/adapters/external/core.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace('resourceName: name,', 'resourceName: `${name}-probe-mismatch`,'));
        await expectBunRed(repo, command, 'api-engine-integration');
      },
    },
  ],
};
