import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<20s) — a source scan, no build.
const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun scripts/validate/forbidden-runtime.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-forbidden-edge-runtime-green',
      description:
        'No route opts into the edge runtime: on the Workers rail every route already runs at the edge under nodejs_compat, and the edge runtime removes the Node APIs OpenNext needs.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'forbidden-edge-runtime');
      },
    },
    {
      name: 'mutation-forbidden-edge-runtime-caught',
      description: 'An `export const runtime = "edge"` in a route turns the forbidden-runtime check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // The declaration builds fine and looks like an optimisation. It changes the
        // route's available API surface underneath OpenNext, so the failure appears
        // only at runtime on the deployed Worker.
        const path = 'src/app/api/manifest/route.ts';
        const source = await repo.read(path);
        await repo.write(path, `${source}\nexport const runtime = 'edge';\n`);
        await expectBunRed(repo, command, 'forbidden-edge-runtime');
      },
    },
  ],
};
