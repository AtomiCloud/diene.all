// COST CLASS: light (<30s) — two structured queries and a file listing. Nothing
// compiles.
//
// Presence row (exists-only, no sabotage). It carries the transferred R-E12
// go-family DOGFOOD obligation, which otherwise has no standing gate: the whole
// L-go family must be consumed as PUBLISHED modules from the Go proxy with a
// `replace` count of zero — one `replace` would make the dogfood vacuous.
//
// ─── LEAD CONDITION ON THIS ROW (binding) ───
// It must ASSERT ON VALUES, never on exit 0. It PRINTS the artifacts it found and
// their COUNT, and it FAILS when a count is ZERO. A presence check that passes on
// an empty result set is exactly the trap that let a 23/23 green run prove
// retracted bytes on another node. Expected: 9 module requires, 0 replaces, 9
// vendored usage skills — all three printed, and all three compared explicitly.
//
// The printing happens INSIDE the dev-shell script, not through a JS logger, so the
// values land in the run's own command transcript and are attributable evidence
// rather than something only the probe process saw.
//
// STRUCTURED QUERY, NOT PATTERN-MATCHING: `go mod edit -json | jq` parses the
// module graph. `grep go.mod` is forbidden for this — a commented-out or
// block-formatted `replace` would fool a text search, and a parser cannot be fooled
// by formatting.
import { expectScriptGreen } from './lib/sandbox-script.ts';

const EXPECTED_MODULES = 9;
const EXPECTED_REPLACES = 0;
const EXPECTED_SKILLS = 9;

const SCRIPT = `graph="$(go mod edit -json)"

echo "=== diene Go module requires ==="
modules="$(printf '%s' "\${graph}" \\
  | jq -r '(.Require // [])[] | select(.Path | startswith("github.com/AtomiCloud/diene.go-")) | .Path + "@" + .Version' \\
  | sort)"
printf '%s\\n' "\${modules}"
module_count="$(printf '%s\\n' "\${modules}" | grep -c . || true)"
echo "module requires: \${module_count}"

echo "=== replace directives ==="
replaces="$(printf '%s' "\${graph}" | jq -r '(.Replace // [])[] | .Old.Path + " => " + .New.Path')"
printf '%s\\n' "\${replaces}"
replace_count="$(printf '%s' "\${graph}" | jq '(.Replace // []) | length')"
echo "replaces: \${replace_count}"

echo "=== unpublished pins (must be none) ==="
unpublished="$(printf '%s\\n' "\${modules}" | grep -v -E '@v[0-9]+\\.[0-9]+\\.[0-9]+$' | grep . || true)"
printf '%s\\n' "\${unpublished}"
unpublished_count="$(printf '%s\\n' "\${unpublished}" | grep -c . || true)"
echo "unpublished pins: \${unpublished_count}"

echo "=== vendored usage skills ==="
skills="$(find .claude/skills/vendor -path '*/diene.go-*' -name SKILL.md | sort)"
printf '%s\\n' "\${skills}"
skill_count="$(printf '%s\\n' "\${skills}" | grep -c . || true)"
echo "vendored usage skills: \${skill_count}"

echo "=== modules whose usage skill is missing (must be none) ==="
skilled="$(printf '%s\\n' "\${skills}" | sed -n 's|^\\.claude/skills/vendor/\\(diene\\.go-[^/]*\\)/.*|\\1|p' | sort -u)"
declared="$(printf '%s\\n' "\${modules}" | sed -n 's|^github\\.com/AtomiCloud/\\(diene\\.go-[^@]*\\)@.*|\\1|p' | sort -u)"
missing="$(comm -23 <(printf '%s\\n' "\${declared}") <(printf '%s\\n' "\${skilled}") | grep . || true)"
printf '%s\\n' "\${missing}"
missing_count="$(printf '%s\\n' "\${missing}" | grep -c . || true)"
echo "modules without a usage skill: \${missing_count}"

echo "SUMMARY \${module_count} module requires, \${replace_count} replaces, \${skill_count} vendored usage skills"

# FAIL ON ZERO — the binding lead condition. An empty result set is a FAILURE, not
# a pass, in both directions.
[ "\${module_count}" -eq 0 ] && { echo "❌ ZERO diene Go module requires — refusing to pass on an empty result set" >&2; exit 1; }
[ "\${skill_count}" -eq 0 ] && { echo "❌ ZERO vendored usage skills — refusing to pass on an empty result set" >&2; exit 1; }
[ "\${module_count}" -ne ${EXPECTED_MODULES} ] && { echo "❌ expected ${EXPECTED_MODULES} module requires, found \${module_count}" >&2; exit 1; }
[ "\${replace_count}" -ne ${EXPECTED_REPLACES} ] && { echo "❌ R-E12 forbids a replace; found \${replace_count}" >&2; exit 1; }
[ "\${skill_count}" -ne ${EXPECTED_SKILLS} ] && { echo "❌ expected ${EXPECTED_SKILLS} vendored usage skills, found \${skill_count}" >&2; exit 1; }
[ "\${unpublished_count}" -ne 0 ] && { echo "❌ \${unpublished_count} require(s) are not pinned to a published release" >&2; exit 1; }
[ "\${missing_count}" -ne 0 ] && { echo "❌ \${missing_count} declared module(s) have no vendored usage skill" >&2; exit 1; }
echo "✅ dogfood artifacts present: ${EXPECTED_MODULES} published requires, ${EXPECTED_REPLACES} replaces, ${EXPECTED_SKILLS} usage skills"
`;

export default {
  contractVersion: 1,
  sandbox: { snapshot: 'git', preserve: ['.direnv'] },
  probes: [
    {
      name: 'presence-lib-dogfood-artifacts',
      description:
        'The nine published diene Go modules are declared with zero replaces, and each has its vendored usage skill.',
      kind: 'baseline',
      async run(repo: any) {
        const result = await expectScriptGreen(
          repo,
          SCRIPT,
          'lib-dogfood-artifacts',
          ['=== diene Go module requires ===', '=== vendored usage skills ===', 'SUMMARY '],
          { timeoutMs: 300000 },
        );
        // Re-assert the three numbers HERE as well, from the printed summary, so the
        // row cannot pass on a script whose guards were weakened or removed. The
        // script refusing zero and the probe refusing zero are two independent
        // checks of the same binding condition.
        const summary = result.transcript.match(
          /SUMMARY (\d+) module requires, (\d+) replaces, (\d+) vendored usage skills/,
        );
        if (!summary) {
          throw new Error(
            `lib-dogfood-artifacts printed no summary line — refusing a pass without values:\n${result.transcript}`,
          );
        }
        const [, moduleCount, replaceCount, skillCount] = summary.map(Number);
        if (moduleCount === 0 || skillCount === 0) {
          throw new Error(
            `lib-dogfood-artifacts passed on an EMPTY result set (${moduleCount} requires, ${skillCount} skills) — this is the exact false-green this row exists to prevent`,
          );
        }
        if (moduleCount !== EXPECTED_MODULES) {
          throw new Error(`expected ${EXPECTED_MODULES} diene Go module requires, the run printed ${moduleCount}`);
        }
        if (replaceCount !== EXPECTED_REPLACES) {
          throw new Error(`expected ${EXPECTED_REPLACES} replace directives, the run printed ${replaceCount}`);
        }
        if (skillCount !== EXPECTED_SKILLS) {
          throw new Error(`expected ${EXPECTED_SKILLS} vendored usage skills, the run printed ${skillCount}`);
        }
      },
    },
  ],
};
