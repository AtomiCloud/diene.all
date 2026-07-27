import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s) — the attribute derivation is pure; the browser SDK is never
// loaded here.
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/faro-attrs.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-faro-init-green',
      description:
        'Every Faro signal carries the full LPSM coordinate, with the landscape taken from the SSR-injected payload.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'faro-init');
      },
    },
    {
      name: 'mutation-faro-init-caught',
      description: 'Dropping the landscape from the attribute map turns the LPSM attribute suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Telemetry still flows, so nothing looks broken — but every signal from
        // every landscape lands in one undifferentiated bucket.
        const path = 'src/lib/faro-attrs/index.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace('  landscape: config.landscape,\n', ''));
        await expectBunRed(repo, command, 'faro-init');
      },
    },
  ],
};
