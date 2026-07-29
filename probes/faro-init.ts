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
      // MEASURED COLLATERAL (family: shared source read by the unit suite). This
      // sabotage edits a real src/ module, and bunfig.unit.toml roots the suite at
      // tests/unit where 16 of 20 files import ../../src/**, so the whole unit run
      // reddens. On the 6f5907a matrix this row broke with control_failed naming
      // diene/bun-base#bun-unit-tests, control output "task: [unit:default] bun test"
      // - the control RAN and FAILED, so the blame was correct, and the empty array
      // here was a positive assertion of no collateral that got believed.
      expectedImpact: ['bun-unit-tests'],
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
