import { expectGreen, expectRed } from './lib/helpers.ts';

const SCRIPT = `#!/usr/bin/env bash
set -euo pipefail
./scripts/local/setup.sh
mkdir -p dist/run
bun -e 'await Bun.write("dist/run/probe-heartbeat.json", JSON.stringify({ pid: 1, state: "healthy", timestamp: new Date().toISOString() }))'
# Secrets are blank-in-yaml (R14/M33); the env tier injects them, exactly as a landscape does.
export ATOMI_AUTH__LOGTO__APP_ID=probe-consumer
export ATOMI_AUTH__LOGTO__APP_SECRET=probe-secret
export ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_ID=probe-management
export ATOMI_AUTH__LOGTO__MANAGEMENT__CLIENT_SECRET=probe-secret
# A throwaway 32-byte key derived at run time — never a committed literal.
ATOMI_ENCRYPTION__KEY="$(bun -e 'process.stdout.write(Buffer.alloc(32, 7).toString("base64"))')"
export ATOMI_ENCRYPTION__KEY
export ATOMI_HEALTH__HEARTBEAT_FILE=dist/run/probe-heartbeat.json
bun run ./src/index.ts --landscape lapras health
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
        const prepared = await repo.exec(
          'mkdir -p dist/probe-config && cp config/settings.yaml config/lapras.settings.yaml dist/probe-config/',
        );
        if (prepared.exitCode !== 0) {
          throw new Error(`could not prepare isolated config fixture: ${prepared.stderr || prepared.stdout}`);
        }
        const path = 'dist/probe-config/lapras.settings.yaml';
        const source = await repo.read(path);
        const patched = source.replace('createBucket: true', "createBucket: 'not-a-boolean'");
        if (patched === source) {
          throw new Error(`no structural overlay value found in ${path}`);
        }
        await repo.write(path, patched);
        await repo.write(
          '.probe-config-layering.sh',
          SCRIPT.replace(
            '# Secrets are blank-in-yaml',
            'export BUN_CONSUMER_CONFIG_DIR=dist/probe-config\n# Secrets are blank-in-yaml',
          ),
        );
        await expectRed(repo, BOOT, 'config-layering');
      },
    },
  ],
};
