import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: heavy — a full docker build where a daemon is reachable, otherwise a
// sub-second static pass over the recipe. See scripts/validate/garden-image.sh:
// the degradation is announced in the run output so a degraded pass can never be
// mistaken for a real build.
const command = 'nix develop .#ci -c ./scripts/validate/garden-image.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-garden-image-green',
      description:
        'The standalone image builds, runs as numeric uid 1001, carries public/ and a non-empty .next/static, and boots server.js.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'garden-image');
      },
    },
    {
      name: 'mutation-garden-image-caught',
      description: 'Dropping the .next/static copy turns the image check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // `output: 'standalone'` traces the server but ships no client chunks, so
        // an image without this copy boots, answers health checks, and renders a
        // page with no JavaScript and no styles — the worst kind of green.
        const path = 'infra/Dockerfile.garden';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/^COPY --from=build .* \/app\/\.next\/static \.\/\.next\/static\n/m, ''));
        await expectBunRed(repo, command, 'garden-image');
      },
    },
  ],
};
