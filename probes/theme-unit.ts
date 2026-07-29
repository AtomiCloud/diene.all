import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/tokens.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-theme-unit-green',
      description:
        'The light and dark token sets declare an identical variable surface, so a theme switch can never leave a variable unset.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'theme-unit');
      },
    },
    {
      name: 'mutation-theme-unit-caught',
      description: 'A variable present in light but missing from dark turns the token parity suite red.',
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
        // An unset variable in one theme inherits the other theme's value, which
        // renders as an unreadable colour pair rather than as an obvious failure.
        const path = 'src/lib/tokens/index.ts';
        const source = await repo.read(path);
        const dark = source.indexOf('dark: {');
        if (dark < 0) throw new Error('dark token block not found');
        await repo.write(path, source.slice(0, dark) + source.slice(dark).replace(/^\s+'--border': .*\n/m, ''));
        await expectBunRed(repo, command, 'theme-unit');
      },
    },
  ],
};
