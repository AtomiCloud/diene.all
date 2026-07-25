import { expectBunGreen } from './lib/bun-command.ts';

// Cost: heavy — one `next build` producing the standby artifact.
//
// The weekly synthetic proper (scripts/ci/standby-synthetic.sh) probes a LIVE
// standby host, which no sandbox has. What this row proves is the mechanism the
// synthetic depends on: that every release can still produce a deployable standby
// artifact. If this rail rots, the CF-outage posture is gone long before the
// synthetic gets a chance to notice.
const command = 'nix develop .#ci -c ./scripts/ci/standby-build.sh';

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-standby-synthetic-green',
      description:
        'The standby rail builds a self-contained Node artifact deployable to any host behind the repointable CNAME.',
      kind: 'baseline',
      async run(repo: any) {
        await expectBunGreen(repo, command, 'standby-synthetic');
        if ((await repo.glob('.next/standalone/server.js')).length !== 1) {
          throw new Error('the standby build produced no standalone server');
        }
      },
    },
  ],
};
