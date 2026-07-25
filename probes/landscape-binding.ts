import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<30s).
const command =
  "nix develop .#ci -c bash -lc './scripts/ci/setup.sh && bun test --config=bunfig.unit.toml tests/unit/landscape-binding.test.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-landscape-binding-green',
      description:
        'Landscape is read from the host binding (prefixed wins, bare fallback, base default) and never browser-detected.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'landscape-binding');
      },
    },
    {
      name: 'mutation-landscape-binding-caught',
      description: 'Detecting the landscape from the browser location turns the binding suite red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Hostname sniffing makes the landscape disagree between the server and
        // client render, which silently mis-tags every telemetry signal.
        const path = 'src/adapters/server-config/index.ts';
        const source = await repo.read(path);
        await repo.write(
          path,
          source.replace(
            "value: process.env['ATOMI_LANDSCAPE'] ?? process.env['LANDSCAPE'] ?? 'base',",
            "value: globalThis.location?.hostname.split('.')[3] ?? 'base',",
          ),
        );
        await expectBunRed(repo, command, 'landscape-binding');
      },
    },
  ],
};
