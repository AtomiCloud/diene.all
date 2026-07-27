// COST CLASS: medium (<3min) — compiles the binary once and boots it twice. A
// lighter proxy cannot prove this mechanism: the property is that validation runs
// ONCE, on the FINAL merged tree, at boot. Only actually booting establishes it.
//
// The row boots the COMPILED artifact against an ISOLATED config fixture root
// (`GO_CONSUMER_ROOT`), so neither branch mutates a committed config layer — a
// mutated `config/settings.yaml` would legitimately redden the constants-sync,
// rebrand, and prettier controls co-selected with this row.
//
// WHY THE SABOTAGE IS AT THE FINAL TIER, measured not assumed:
// `base < overlay < env`, and only the merge validates. An INVALID INTERMEDIATE
// layer whose value the env tier overwrites with a valid one boots GREEN — I ran
// exactly that (`lapras.settings.yaml: createBucket: not-a-boolean` +
// `ATOMI_DBINIT__CREATEBUCKET=true` → exit 0, healthy heartbeat printed). So a
// sabotage placed in the overlay would prove nothing about fail-fast. The fault
// therefore lands on the LAST tier that contributes to the merged value, which
// makes the FINAL merged layer invalid, and the boot fail-fasts with a validation
// Problem before any dependency is dialled.
import { expectScriptGreen, expectScriptRed } from './lib/sandbox-script.ts';

// Secrets are blank-in-YAML (R14/M33) and injected by the environment tier
// exactly as a landscape does. The AES key is DERIVED at run time — never a
// committed literal. The heartbeat fixture is written fresh so `health` reports a
// healthy, dependency-blind verdict; `health` never dials postgres/redis/S3, which
// is why this row needs no local stack.
function bootScript(finalTierOverride: string): string {
  return `fixture="$(mktemp -d)"
cleanup() { rm -rf "\${fixture}"; }
trap cleanup EXIT
mkdir -p "\${fixture}/config" "\${fixture}/dist/run"
cp config/settings.yaml config/*.settings.yaml "\${fixture}/config/"
printf '{"pid":1,"state":"healthy","timestamp":"%s"}\\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\
  >"\${fixture}/dist/run/probe-heartbeat.json"
./scripts/local/setup.sh
./scripts/local/build.sh
test -x dist/go-consumer || { echo "❌ compiled artifact is absent" >&2; exit 1; }
layers="$(find "\${fixture}/config" -name '*.yaml' | wc -l | tr -d ' ')"
echo "\${layers} configuration layers in the fixture root"
[ "\${layers}" -lt 2 ] && { echo "❌ fewer than 2 layers — a single-layer boot cannot prove layering" >&2; exit 1; }
export GO_CONSUMER_ROOT="\${fixture}"
export ATOMI_AUTH__IDP__MANAGEMENT__CLIENT_ID=probe-management
export ATOMI_AUTH__IDP__MANAGEMENT__CLIENT_SECRET=probe-secret
export ATOMI_AUTH__MINTING__CLIENT_ID=probe-minting
export ATOMI_AUTH__MINTING__CLIENT_SECRET=probe-secret
ATOMI_ENCRYPTION__KEY="$(head -c32 /dev/zero | base64 -w0)"
export ATOMI_ENCRYPTION__KEY
export ATOMI_HEALTH__HEARTBEATFILE=dist/run/probe-heartbeat.json
${finalTierOverride}
echo "=== boot: base + lapras overlay + environment ==="
./dist/go-consumer --landscape lapras health
echo "✅ the final merged configuration validated and the worker booted"
`;
}

const HEALTHY = bootScript('# no final-tier sabotage on the healthy branch');

// ONE fault: the LAST tier that contributes to `dbInit.createBucket` supplies a
// value of the wrong TYPE, so the FINAL MERGED tree violates the schema. The key
// is reached structurally through the documented `ATOMI_` + `__` nesting
// convention rather than by editing a named sample file.
const SABOTAGED = bootScript('export ATOMI_DBINIT__CREATEBUCKET=not-a-boolean');

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-config-layering-green',
      description: 'Base plus sparse landscape overlay plus environment override validate after the final merge only.',
      kind: 'baseline',
      async run(repo: any) {
        // Assert on printed VALUES: the boot must print the health verdict, and the
        // fixture must actually have carried more than one layer — a one-layer boot
        // exercises no layering at all and is refused inside the script.
        await expectScriptGreen(
          repo,
          HEALTHY,
          'config-layering',
          ['configuration layers in the fixture root', '"healthy":true', 'the final merged configuration validated'],
          { timeoutMs: 900000 },
        );
      },
    },
    {
      name: 'mutation-config-layering-caught',
      description: 'A final-tier value violating the schema makes the merged layer invalid and boot fail-fast red.',
      kind: 'mutation',
      expectedImpact: [],
      async run(repo: any) {
        const result = await expectScriptRed(repo, SABOTAGED, 'config-layering', { timeoutMs: 900000 });
        // The row must fail for the RIGHT reason. Without this, a build failure or
        // a missing fixture would also exit non-zero and read as a caught sabotage.
        if (!/load configuration|[Vv]alidation/.test(result.transcript)) {
          throw new Error(
            `config-layering went red for a non-validation reason — the fail-fast path was not exercised:\n${result.transcript}`,
          );
        }
      },
    },
  ],
};
