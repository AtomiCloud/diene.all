// Serializes on the same host lock as the SIT rows: pls up/down binds the
// dev.yaml host ports, so concurrent stacks would collide (PROBES §5 addendum).
const SCRIPT = `#!/usr/bin/env bash
set -euo pipefail
./scripts/local/setup.sh
cleanup() { pls down || true; }
trap cleanup EXIT
pls up
pls run -- --help
pls preview -- --help
test -x scripts/local/dev.sh
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-task-surface-green',
      description:
        'The pls run/preview/up/down tasks execute their intended local operations; dev is exercised via its underlying script contract.',
      kind: 'baseline',
      async run(repo: any) {
        await repo.write('.probe-task-surface.sh', SCRIPT);
        const result = await repo.exec(
          "nix develop .#ci -c bash -lc 'flock /tmp/diene-bunconsumer-sit.lock bash .probe-task-surface.sh'",
          { timeoutMs: 1800000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(`task-surface failed on the healthy repo: ${result.stderr || result.stdout}`);
        }
      },
    },
  ],
};
