// COST CLASS: medium (<3min) — a scoped unit run plus a Testcontainers-backed
// integration run. Not heavy: only the packages that own these three seams are
// selected, not the whole tier.
//
// Proven-only smoke. THREE seams, one row because the goal names them as one
// feature ("HttpClient/AuthClient/Encryptor"): the published api-engine client
// tree, the auth-engine client-credentials source behind its token cache
// (including refresh on JWT expiry), and the AES-256-GCM encryptor used for
// encrypt-before-store. Their enforcement lives in the unit and int GATES, which
// carry the sabotages; this row asserts the baselines genuinely EXERCISE the seams.
import { expectScriptGreen } from './lib/sandbox-script.ts';

// `go test -run` matching nothing exits 0 and prints "no tests to run", so the
// script counts the selected tests and REFUSES a zero-test selection before
// running them. `-v` makes each executed test name appear in the transcript, which
// is what the probe then asserts on.
const SCRIPT = `./scripts/local/setup.sh

echo "=== unit: encryption and published-client seams ==="
unit_packages="$(go list ./tests/unit/... | grep -E '/(encryption|publishedapi)$' || true)"
unit_count="$(printf '%s\\n' "\${unit_packages}" | grep -c . || true)"
echo "\${unit_count} unit packages selected: \${unit_packages}"
[ "\${unit_count}" -eq 0 ] && { echo "❌ no encryption/published-client unit packages found" >&2; exit 1; }
# shellcheck disable=SC2086
go test -count=1 -v \${unit_packages}

echo "=== int: published clients and the token store against real dependencies ==="
int_packages="$(go list ./tests/int/... | grep -E '/redis$' || true)"
int_count="$(printf '%s\\n' "\${int_packages}" | grep -c . || true)"
echo "\${int_count} integration packages selected: \${int_packages}"
[ "\${int_count}" -eq 0 ] && { echo "❌ no token-store integration package found" >&2; exit 1; }
# shellcheck disable=SC2086
go test -count=1 -v \${int_packages}
echo "✅ client, auth token, and encryptor seams exercised"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'baseline-http-auth-encryptor-green',
      description:
        'Unit and integration baselines exercise the published client tree, the auth token cache, and the symmetric encryptor.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await expectScriptGreen(
          repo,
          SCRIPT,
          'http-auth-encryptor',
          ['unit packages selected', 'integration packages selected', 'seams exercised'],
          { timeoutMs: 1200000 },
        );
        // Refuse a vacuous selection: `go test` over a package with no matching
        // tests exits 0. The transcript must show tests that actually RAN.
        for (const vacuous of ['no tests to run', 'no test files']) {
          if (result.transcript.includes(vacuous)) {
            throw new Error(`http-auth-encryptor selected packages that reported ${JSON.stringify(vacuous)}`);
          }
        }
        const passed = [...result.transcript.matchAll(/^--- PASS: (\S+)/gm)].map(match => match[1]);
        if (passed.length === 0) {
          throw new Error(
            `http-auth-encryptor exited 0 but no test reported PASS — refusing a vacuous run:\n${result.transcript}`,
          );
        }
        // Each of the three named seams must appear in what actually ran; a row
        // that silently lost one of them would still exit 0.
        const seams: Record<string, RegExp> = {
          encryptor: /Encrypt|AES/i,
          'client tree': /ClientTree|Client/i,
          'auth token': /Token|Credential/i,
        };
        for (const [seam, pattern] of Object.entries(seams)) {
          if (!passed.some(name => pattern.test(name))) {
            throw new Error(
              `http-auth-encryptor ran ${passed.length} tests but none exercised the ${seam} seam: ${passed.join(', ')}`,
            );
          }
        }
      },
    },
  ],
};
