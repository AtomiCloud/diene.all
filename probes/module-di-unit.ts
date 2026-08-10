import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/module-di.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-module-di-unit-green',
      description:
        'Modules are declared under unique ids, registered once, and resolved through the registry rather than constructed by consumers.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'module-di-unit');
      },
    },
    {
      name: 'mutation-module-di-unit-caught',
      description: 'Registering the same module id twice turns the DI wiring suite red.',
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
        // A duplicate id makes registration fail at boot; uniqueness is the
        // invariant that keeps that failure branch unreachable in production.
        const path = 'src/adapters/atomi/modules.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace("contentStore: 'content-store',", "contentStore: 'problem-views',"));
        await expectBunRed(repo, command, 'module-di-unit');
      },
    },
  ],
};
