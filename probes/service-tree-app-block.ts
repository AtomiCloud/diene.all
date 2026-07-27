// COST CLASS: light (<30s) — a yq query per committed configuration layer.
//
// Presence row (exists and parses, no sabotage). Every configuration must carry the
// full LPSM + version service-tree block: it is what every telemetry resource
// attribute, every chart label, and every problem type URI is projected from.
//
// STRUCTURED query over EVERY committed layer, not just the base — a sparse overlay
// is allowed to omit the block, but if it declares any part of it, the part it
// declares must be non-blank. And because "found nothing" must never read as
// "nothing wrong", the row prints how many layers it inspected and refuses zero.
import { expectScriptGreen } from './lib/sandbox-script.ts';

const FIELDS = ['landscape', 'platform', 'service', 'module', 'version'];

const SCRIPT = `layers="$(find config -maxdepth 1 -name 'settings.yaml' -o -maxdepth 1 -name '*.settings.yaml' | sort)"
printf '%s\\n' "\${layers}"
layer_count="$(printf '%s\\n' "\${layers}" | grep -c . || true)"
echo "configuration layers inspected: \${layer_count}"
[ "\${layer_count}" -eq 0 ] && { echo "❌ ZERO configuration layers found — refusing to pass on an empty scan" >&2; exit 1; }

base="config/settings.yaml"
[ -s "\${base}" ] || { echo "❌ base configuration \${base} is missing or empty" >&2; exit 1; }

echo "=== base layer must carry the COMPLETE app block ==="
base_present=0
base_missing=0
for field in ${FIELDS.join(' ')}; do
  value="$(yq -r ".app.\${field} // \\"\\"" "\${base}")"
  if [ -z "\${value}" ] || [ "\${value}" = "null" ]; then
    echo "❌ app.\${field} absent or blank in \${base}"
    base_missing=$((base_missing + 1))
  else
    echo "\${base} app.\${field} = \${value}"
    base_present=$((base_present + 1))
  fi
done

echo "=== every overlay that declares an app field must not blank it ==="
overlay_violations=0
for layer in \${layers}; do
  [ "\${layer}" = "\${base}" ] && continue
  for field in ${FIELDS.join(' ')}; do
    yq -e ".app | has(\\"\${field}\\")" "\${layer}" >/dev/null 2>&1 || continue
    value="$(yq -r ".app.\${field} // \\"\\"" "\${layer}")"
    if [ -z "\${value}" ] || [ "\${value}" = "null" ]; then
      echo "❌ \${layer} declares app.\${field} but blanks it"
      overlay_violations=$((overlay_violations + 1))
    else
      echo "\${layer} app.\${field} = \${value}"
    fi
  done
done

echo "SUMMARY \${layer_count} layers, \${base_present}/${FIELDS.length} base app fields, \${base_missing} missing, \${overlay_violations} overlay violations"
[ "\${base_present}" -eq 0 ] && { echo "❌ ZERO app fields resolved in the base layer" >&2; exit 1; }
[ "\${base_missing}" -ne 0 ] && { echo "❌ \${base_missing} service-tree field(s) absent from \${base}" >&2; exit 1; }
[ "\${overlay_violations}" -ne 0 ] && { echo "❌ \${overlay_violations} overlay(s) blank a declared service-tree field" >&2; exit 1; }
echo "✅ the service-tree app block is complete in \${base} and intact across \${layer_count} layers"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-service-tree-app-block',
      description: 'The base configuration carries the full LPSM/version service-tree block and no overlay blanks it.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await expectScriptGreen(repo, SCRIPT, 'service-tree-app-block', ['SUMMARY '], {
          timeoutMs: 300000,
        });
        const summary = result.transcript.match(
          /SUMMARY (\d+) layers, (\d+)\/(\d+) base app fields, (\d+) missing, (\d+) overlay violations/,
        );
        if (!summary) {
          throw new Error(
            `service-tree-app-block printed no summary — refusing a pass without values:\n${result.transcript}`,
          );
        }
        const [, layers, present, expected, missing, violations] = summary.map(Number);
        if (layers === 0 || present === 0) {
          throw new Error(
            `service-tree-app-block passed on an EMPTY scan (${layers} layers, ${present} fields resolved)`,
          );
        }
        if (present !== expected || missing !== 0 || violations !== 0) {
          throw new Error(
            `service-tree-app-block expected ${expected} base fields, 0 missing, 0 violations; the run printed ${present}, ${missing}, ${violations}`,
          );
        }
      },
    },
  ],
};
