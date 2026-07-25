import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<15s) — a source-graph read, no build.
const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun scripts/validate/pure-renderer.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-pure-renderer-lint-green',
      description:
        'Every page renders translations and mounts components only: no service, adapter, or data-client import lives in a page.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'pure-renderer-lint');
      },
    },
    {
      name: 'mutation-pure-renderer-lint-caught',
      description: 'A service import inside a page turns the pure-renderer arch lint red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // A page that reaches for a backend binding directly still renders, and it
        // takes the layer boundary with it — the lint is the only thing that says so.
        const path = 'src/app/[locale]/page.tsx';
        const source = await repo.read(path);
        await repo.write(path, `import { backendBindings } from '@/adapters/external/core';\n${source}`);
        await expectBunRed(repo, command, 'pure-renderer-lint');
      },
    },
  ],
};
