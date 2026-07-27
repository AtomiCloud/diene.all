import { expectBunGreen, expectBunRed } from './lib/bun-command.ts';

// Cost: light (<20s) — a workflow and script scan, no build.
const command = "nix develop .#ci -c bash -lc './scripts/local/setup.sh && bun scripts/validate/deploy-policy.ts'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-deploy-policy-green',
      description:
        'CI only UPLOADS tagged Worker versions; promotion to a live landscape is out-of-band, so no CI path ever runs a direct deploy.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'deploy-policy');
      },
    },
    {
      name: 'mutation-deploy-policy-caught',
      description: 'A direct `wrangler deploy` in a CI script turns the deploy-policy check red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        // A deploy line next to the upload line looks like a harmless convenience
        // and takes the release out of the promotion system's hands: CI would push
        // straight to live traffic with no pinned version to roll back to.
        const path = 'scripts/ci/upload.sh';
        const source = await repo.read(path);
        await repo.write(path, `${source}\nwrangler deploy --env pichu\n`);
        await expectBunRed(repo, command, 'deploy-policy');
      },
    },
  ],
};
