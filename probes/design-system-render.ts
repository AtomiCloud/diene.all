import { expectBunGreen } from './lib/bun-command.ts';

// Cost: heavy — one `next build`. Rendering every rule-defaulting component through
// a real build is the proof that the design system compiles and prerenders; there is
// deliberately no screenshot or golden comparison anywhere in this tree.
const command =
  'nix develop .#ci -c bash -lc \'./scripts/ci/setup.sh && export PATH="$(pwd)/node_modules/.bin:$PATH" && next build && ./scripts/local/standalone-assets.sh\'';

const ARTIFACTS = ['.next/standalone/server.js', '.next/server/app', '.next/static'];

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-design-system-render-green',
      description:
        'The app builds and prerenders: every page and rule-defaulting component compiles, and the standalone artifact carries its server and client chunks.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'design-system-render');
        for (const artifact of ARTIFACTS) {
          if ((await repo.glob(artifact)).length !== 1) {
            throw new Error(`build produced no ${artifact}`);
          }
        }
        // `output: 'standalone'` traces the server but ships neither public/ nor
        // .next/static — the assets step copies both, and an app without client
        // chunks boots and then renders nothing.
        if ((await repo.glob('.next/standalone/.next/static')).length !== 1) {
          throw new Error('the standalone artifact carries no client chunks');
        }
      },
    },
  ],
};
