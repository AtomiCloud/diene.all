import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<20s).
//
// This row shares its validation SCRIPT with `wrangler-config` but is a distinct
// mechanism in the matrix: `wrangler-config` covers the Worker's deployment shape
// (compatibility date, flags, per-landscape envs), while this row covers the ISR
// storage triple specifically — R2 incremental cache + Durable Object queue + D1
// tag cache, never KV. Each row therefore sabotages a DIFFERENT binding, so
// neither one's evidence stands in for the other's.
const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun scripts/validate/wrangler-config.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-isr-bindings-green',
      description:
        'The ISR triple is bound as R2 for the incremental cache, a Durable Object for the revalidation queue, and D1 for the tag cache.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'isr-bindings');
      },
    },
    {
      name: 'mutation-isr-bindings-caught',
      description: 'A missing R2 incremental-cache bucket turns the ISR binding check red.',
      kind: 'mutation',
      expectedImpact: ['wrangler-config'],
      async run(repo: any) {
        // With no R2 bucket the incremental cache falls back to per-isolate memory:
        // the app is correct and unboundedly slower, and every isolate re-renders
        // every page. Nothing fails, so only this check notices.
        const path = 'wrangler.toml';
        const source = await repo.read(path);
        await repo.write(path, source.replace(/\n\[\[r2_buckets\]\][\s\S]*?bucket_name = "[^"]*"\n/, '\n'));
        await expectBunRed(repo, command, 'isr-bindings');
      },
    },
  ],
};
