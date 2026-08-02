import { BUN_PROBE_SANDBOX, BUN_PROBE_SETUP } from './lib/bun.ts';
import { expectGreen } from './lib/helpers.ts';

const smoke = 'nix develop --no-write-lock-file .#ci -c pls build';
const artifact = 'dist/index.js';

export default {
  contractVersion: 1,
  sandbox: BUN_PROBE_SANDBOX,
  setup: BUN_PROBE_SETUP,
  probes: [
    {
      name: 'baseline-bun-build-green',
      description: 'The bundle builds and the declared artifact is a real bundle, not an empty file.',
      kind: 'baseline',
      async run(repo: any) {
        await expectGreen(repo, smoke, 'bun-build');
        if ((await repo.glob(artifact)).length !== 1) {
          throw new Error(`the build reported success without producing ${artifact}`);
        }
        // The promise is about the artifact: a zero-byte or stub file passes an exit-code check.
        const bundle = await repo.read(artifact);
        if (bundle.length < 1024) {
          throw new Error(`${artifact} is ${bundle.length} bytes, which is not a bundled entry point`);
        }
      },
    },
  ],
};
