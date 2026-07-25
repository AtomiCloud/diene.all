import { expectGreen, expectRed } from './lib/helpers.ts';

const SCRIPT = `#!/usr/bin/env bash
set -euo pipefail
./scripts/local/setup.sh
mkdir -p dist/run
bun -e 'await Bun.write("dist/run/probe-heartbeat.json", JSON.stringify({ pid: 1, state: "healthy", timestamp: new Date().toISOString() }))'
ATOMI_HEALTH__HEARTBEAT_FILE=dist/run/probe-heartbeat.json bun run ./src/index.ts --landscape lapras health
`;

const BOOT = "nix develop .#ci -c bash -lc 'bash .probe-config-layering.sh'";

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-config-layering-green',
      description: 'Base plus sparse landscape overlay plus env override validate after the final merge only.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write('.probe-config-layering.sh', SCRIPT);
        await expectGreen(repo, BOOT, 'config-layering');
      },
    },
    {
      name: 'mutation-config-layering-caught',
      description: 'A landscape overlay violating the zod schema turns boot fail-fast red.',
      kind: 'mutation',
      async run(repo: any) {
        const source = await repo.read('config/lapras.settings.yaml');
        const patched = source.replace('createBucket: true', "createBucket: 'not-a-boolean'");
        if (patched === source) {
          throw new Error('no structural overlay value found in config/lapras.settings.yaml');
        }
        await repo.write('config/lapras.settings.yaml', patched);
        await repo.write('.probe-config-layering.sh', SCRIPT);
        await expectRed(repo, BOOT, 'config-layering');
      },
    },
  ],
};
