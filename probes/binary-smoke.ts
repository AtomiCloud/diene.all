import { BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectGreen } from './lib/helpers.ts';

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-binary-smoke-green',
      description: 'Every declared workspace binary answers a real smoke invocation.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, 'nix develop .#default -c ./scripts/validate/binary-smoke.sh', 'binary-smoke');
      },
    },
  ],
};
