import type { ProbeDefinition } from "@cyanprint/contracts";

const script = `#!/usr/bin/env bash
set -euo pipefail

git --version
git rev-parse --is-inside-work-tree
treefmt --version
nix fmt --no-write-lock-file -- --no-cache
jq --version
jq -n '1 + 1' | grep -qx 2
yq --version
yq -n '.probe = true' | grep -q 'probe: true'
gomplate --version
test "$(gomplate -i '{{ add 1 1 }}')" = 2
bash --version
test "$(bash -lc 'printf probe')" = probe
`;

const definition: ProbeDefinition = {
  contractVersion: 1,
  sandbox: { snapshot: "git" },
  probes: [
    {
      name: "declared-binary-inventory-operates",
      description:
        "The root package inventory answers version or help and completes representative real operations.",
      kind: "baseline",
      timeoutMs: 240000,
      async run(repo) {
        await repo.write(".probe-binary-smoke.sh", script);
        const result = await repo.exec(
          "nix develop --no-write-lock-file .#default -c bash .probe-binary-smoke.sh",
          { timeoutMs: 240000 },
        );
        if (result.exitCode !== 0) {
          throw new Error(
            `binary smoke failed: ${result.stderr || result.stdout}`,
          );
        }
      },
    },
  ],
};

export default definition;
