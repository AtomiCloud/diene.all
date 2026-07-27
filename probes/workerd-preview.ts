import { expectBunGreen } from './lib/bun-command.ts';

// Cost: heavy — an OpenNext build plus a real workerd boot. `next dev` and the
// standalone Node server both prove the app runs on Node; only workerd proves it runs
// on the runtime it actually deploys to, which is the point of this row.
const command = 'nix develop .#ci -c ./scripts/ci/workerd-preview.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-workerd-preview-green',
      description:
        'The OpenNext artifact boots under real workerd and renders the home page through the locale redirect.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'workerd-preview');
      },
    },
  ],
};
