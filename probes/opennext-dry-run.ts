import { expectBunGreen } from './lib/bun-command.ts';

// Cost: heavy — an OpenNext build plus three wrangler dry-runs. This is the Layer B
// posture: the build runs WITHOUT Faro credentials, so the source-map uploader stays
// unmounted and the dry-run is exactly the no-credential path PR CI takes.
const command = 'nix develop .#ci -c ./scripts/ci/opennext-build.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-opennext-dry-run-green',
      description:
        'The OpenNext adapter builds a Worker artifact that passes a wrangler dry-run for every promotion landscape.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'opennext-dry-run');
        if ((await repo.glob('.open-next/worker.js')).length !== 1) {
          throw new Error('the OpenNext build produced no .open-next/worker.js');
        }
      },
    },
  ],
};
