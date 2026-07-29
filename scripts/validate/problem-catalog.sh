#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

catalog_file="infra/primordial_chart/files/problems.json"

# The runtime problem registry is the single source of truth. Its type URIs are
# minted by the @atomicloud/diene.problems ErrorPortal contract (which emits the
# canonical `/docs/<landscape>/<platform>/<service>/<module>/<version>/<id>`
# path), so the committed primordial catalog must match id, type, title, and
# status exactly — including compiled_address_stale.
# This is intentionally single-quoted: `${...}` belongs to Bun's template
# literal and must never be expanded by the shell.
# shellcheck disable=SC2016
bun -e '
  const { IntakeProblemCatalog, defaultIntakePortal } = await import("./src/http/intake/problems.ts");
  const problems = new IntakeProblemCatalog(defaultIntakePortal).registry
    .list()
    .map(problem => ({ id: problem.id, type: problem.type, title: problem.title, status: problem.status }))
    .sort((left, right) => left.id.localeCompare(right.id));
  process.stdout.write(`${JSON.stringify({ problems }, null, 2)}\n`);
' >"${tmp}/runtime.json"

jq -S '.problems |= sort_by(.id)' "${tmp}/runtime.json" >"${tmp}/runtime.canon.json"
jq -S '.problems |= sort_by(.id)' "${catalog_file}" >"${tmp}/catalog.canon.json"

if ! diff -u "${tmp}/catalog.canon.json" "${tmp}/runtime.canon.json"; then
  echo "❌ primordial problem catalog does not match the runtime problem registry" >&2
  exit 1
fi

# Every published type must be a docs URI on the canonical problems host.
jq -e '.problems | length > 0 and all(.[];
  (.type | startswith("https://problems.atomi.cloud/docs/")) and
  (.status | type == "number"))' "${catalog_file}" >/dev/null

echo "✅ Problem catalog matches the runtime problem registry"
