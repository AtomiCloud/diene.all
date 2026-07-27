// COST CLASS: light (<30s) — one yq parse.
//
// Presence row (exists and PARSES, no sabotage). `config/dev.yaml` is the single
// local-dev control file: `up.sh`, `down.sh`, and `with-dev-env.sh` all read their
// ports, credentials, and endpoints out of it, so an unparseable or gutted file
// silently breaks every local operation.
//
// A STRUCTURED query, never a text search: `yq -e` parses the document, so a file
// that merely CONTAINS the right words but is not valid YAML cannot pass. And
// because a presence check that succeeds on an empty document is the classic false
// green, the row asserts the keys its consumers actually read are PRESENT and
// prints how many it found.
import { expectScriptGreen } from './lib/sandbox-script.ts';

// These are exactly the paths `scripts/local/{up,down,with-dev-env}.sh` dereference.
const REQUIRED = [
  '.compose.project',
  '.postgres.host',
  '.postgres.port',
  '.postgres.database',
  '.postgres.username',
  '.redis.host',
  '.redis.port',
  '.storage.endpoint',
  '.storage.accessKeyId',
  '.otel.endpoint',
];

const SCRIPT = `subject="config/dev.yaml"
[ -s "\${subject}" ] || { echo "❌ \${subject} is missing or empty" >&2; exit 1; }

echo "=== \${subject} parses as YAML ==="
yq -e '.' "\${subject}" >/dev/null
echo "parsed \${subject}"

echo "=== required local-dev keys ==="
missing=0
found=0
for path in ${REQUIRED.join(' ')}; do
  value="$(yq -r "\${path} // \\"\\"" "\${subject}")"
  if [ -z "\${value}" ] || [ "\${value}" = "null" ]; then
    echo "❌ \${path} is absent or blank"
    missing=$((missing + 1))
  else
    echo "\${path} = \${value}"
    found=$((found + 1))
  fi
done
echo "SUMMARY \${found} required keys present, \${missing} absent"
[ "\${found}" -eq 0 ] && { echo "❌ ZERO required keys resolved — refusing to pass on an empty document" >&2; exit 1; }
[ "\${missing}" -ne 0 ] && { echo "❌ \${missing} required local-dev key(s) absent from \${subject}" >&2; exit 1; }
echo "✅ \${subject} exists, parses, and carries all \${found} required local-dev keys"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-config-dev-yaml',
      description: 'The single local-dev control file exists, parses as YAML, and carries every key its scripts read.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await expectScriptGreen(repo, SCRIPT, 'config-dev-yaml', ['SUMMARY '], {
          timeoutMs: 300000,
        });
        const summary = result.transcript.match(/SUMMARY (\d+) required keys present, (\d+) absent/);
        if (!summary) {
          throw new Error(`config-dev-yaml printed no summary — refusing a pass without values:\n${result.transcript}`);
        }
        const [, present, absent] = summary.map(Number);
        if (present === 0) {
          throw new Error('config-dev-yaml passed with ZERO keys resolved — an empty document is not a present one');
        }
        if (present !== REQUIRED.length || absent !== 0) {
          throw new Error(
            `config-dev-yaml expected ${REQUIRED.length} keys present and 0 absent, the run printed ${present} and ${absent}`,
          );
        }
      },
    },
  ],
};
