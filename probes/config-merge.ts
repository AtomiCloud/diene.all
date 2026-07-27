import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s) — the unit tier alone.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/config-merge.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-config-merge-green',
      description:
        'The four config tiers resolve in precedence order: base YAML, landscape overlay, build-time env, runtime env.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'config-merge');
      },
    },
    {
      name: 'mutation-config-merge-caught',
      description: 'A landscape overlay that no longer overrides the base file turns the precedence suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Strip the overlay's own baseUrl: the pichu tree then keeps the base
        // value, which is exactly the silent misconfiguration this gate exists
        // to catch (every landscape reporting the base landscape's URLs).
        const path = 'config/pichu.config.yaml';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/^seo:\n  baseUrl: .*\n/m, ''));
        await expectBunRed(repo, command, 'config-merge');
      },
    },
  ],
};
