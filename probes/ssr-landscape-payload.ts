import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: heavy — a next build plus one Playwright slice against the standalone
// server. The SSR payload is only observable in a real render, so the build is
// unavoidable for this mechanism.
const command =
  'nix develop .#ci -c bash -lc \'./scripts/ci/setup.sh && export PATH="$(pwd)/node_modules/.bin:$PATH" && next build && ./scripts/local/standalone-assets.sh && playwright test well-known.spec.ts\'';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-ssr-landscape-payload-green',
      description:
        'The server injects the resolved landscape into the client payload so one artifact reports correctly under every binding.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'ssr-landscape-payload');
      },
    },
    {
      name: 'mutation-ssr-landscape-payload-caught',
      description: 'Omitting the landscape from the client-safe projection turns the SSR payload journey red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // Without the injected landscape the browser has no way to know which
        // landscape served it, so every client signal is mis-attributed.
        const path = 'src/adapters/server-config/index.ts';
        const source = await repo.read(path);
        await repo.write(path, source.replace('landscape: currentLandscape,', "landscape: '',"));
        await expectBunRed(repo, command, 'ssr-landscape-payload');
      },
    },
  ],
};
