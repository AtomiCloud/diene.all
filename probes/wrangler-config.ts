import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<20s) — a TOML read, no build.
const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun scripts/validate/wrangler-config.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-wrangler-config-green',
      description:
        'The Worker config declares the compatibility date, the nodejs_compat flags, the asset binding, and one env per promotion landscape.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'wrangler-config');
      },
    },
    {
      name: 'mutation-wrangler-config-caught',
      description: 'A missing D1 tag-cache binding turns the Worker config check red.',
      kind: 'mutation',
      expectedImpact: ['isr-bindings'],
      async run(repo: any) {
        // Without the tag cache the Worker still deploys and still serves: only
        // on-demand revalidation quietly stops working, which surfaces as stale
        // pages days later rather than as a failed deploy.
        const path = 'wrangler.toml';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/\n\[\[d1_databases\]\][\s\S]*?database_id = "[^"]*"\n/, '\n'));
        await expectBunRed(repo, command, 'wrangler-config');
      },
    },
  ],
};
