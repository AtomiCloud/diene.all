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
      expectedImpact: [],
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
