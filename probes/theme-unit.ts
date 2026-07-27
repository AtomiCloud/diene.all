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
      expectedImpact: [],
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
