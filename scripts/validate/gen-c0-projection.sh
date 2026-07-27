#!/usr/bin/env bash
# Downstream C0 projection generator for diene_api_engine.
# Projects the §2 problem envelope from the neutral release cases into the
# member package's test/fixtures/c0/. Canonical form is `jq -S --indent 2`
# (recursively sorted keys, integers, LF, one trailing newline) — identical to
# the release cases. Host-safe: bash + jq only. `--check` fails closed on drift.
#
# RECOVERED under R-E1a from the preserved C0-migration worktree
# (.worktrees/dart-api-c0mig-mrv4vyux, branch diene-cond-5b1b11-api@7c1969a),
# byte-preserved since 2026-07-21 at sha256
# c8f5fad15d9d10f2da7c3dc3364faa452b6416b989b3c11f3ebacb404a7969c3.
# The ONE substantive change from the preserved bytes: the paths are now
# ROOT-ANCHORED via `git rev-parse --show-toplevel`. The preserved script read
# `contracts/c0/...` and wrote `test/fixtures/c0/...` as sibling CWD-relative
# paths, which was correct only while the package sat at the repo root. Under
# the dart-lib member layout contracts/ is at the root and the fixtures are
# under packages/diene_api_engine/, so CWD-relative paths cannot address both.
set -euo pipefail

mode="${1:-write}"
root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

src="contracts/c0/cases/problem.json"
outdir="packages/diene_api_engine/test/fixtures/c0"

[ -f "${src}" ] || {
  echo "❌ release case source is missing: ${src}" >&2
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

jq -S --indent 2 ".cases.envelopes.valid[0]" "${src}" >"${tmp}/problem_envelope.json"
# Refuse on an empty projection: `jq` emits the literal `null` for a missing
# path and exits 0, so "the selector found nothing" and "the selector found a
# document" would otherwise produce the same green.
if [ "$(cat "${tmp}/problem_envelope.json")" = "null" ]; then
  echo "❌ projection selector matched nothing in ${src}" >&2
  exit 1
fi
(cd "${tmp}" && sha256sum problem_envelope.json) >"${tmp}/SHA256SUMS"

if [ "${mode}" = "--check" ]; then
  cmp "${tmp}/problem_envelope.json" "${outdir}/problem_envelope.json"
  cmp "${tmp}/SHA256SUMS" "${outdir}/SHA256SUMS"
  echo "✅ projection --check: problem_envelope.json matches the release projection"
else
  mkdir -p "${outdir}"
  cp "${tmp}/problem_envelope.json" "${outdir}/problem_envelope.json"
  cp "${tmp}/SHA256SUMS" "${outdir}/SHA256SUMS"
  echo "✅ wrote ${outdir}/problem_envelope.json (+ SHA256SUMS) from ${src}"
fi
