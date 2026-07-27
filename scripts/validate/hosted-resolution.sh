#!/usr/bin/env bash
set -euo pipefail

# Hosted-resolution evidence for the publishable member.
#
# The other root gates run against THIS worktree, whose `.dart_tool`/lockfile
# state is whatever previous commands left behind and whose resolution a
# developer-local `pubspec_overrides.yaml` could redirect. That is not evidence
# about what an external consumer gets. This gate resolves the member in a
# CLEAN temporary workspace with no overrides and no inherited lock, then prints
# three values per hosted dependency:
#
#   declared constraint | freshly resolved version | current registry latest
#
# and fails closed on a mismatch, on a resolution failure, or on a registry
# failure. It never asserts a hard-coded resolved version: pub is free to move
# within the caret range, and pinning the resolved value here would turn every
# upstream patch release into a red gate. What it DOES assert is that fresh
# resolution lands on the newest version satisfying the declared constraint —
# so a stale or retracted local graph cannot masquerade as consumer truth.
#
# Network is required. A registry that cannot be reached is a FAILURE, not a
# skip: silently degrading to "could not check" is the vacuous-pass shape this
# gate exists to prevent.

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

member_dir="packages/diene_config"
member_pubspec="${member_dir}/pubspec.yaml"
registry="${PUB_HOSTED_URL:-https://pub.dev}"

[[ -f ${member_pubspec} ]] || {
  echo "❌ ${member_pubspec} is missing" >&2
  exit 1
}

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

fail=0
bad() {
  printf '❌ %s\n' "$*" >&2
  fail=1
}

# Refuse to produce evidence from a polluted venue. ---------------------------
echo '→ proof venue is override-free'
for override in pubspec_overrides.yaml "${member_dir}/pubspec_overrides.yaml"; do
  if [[ -e ${override} ]]; then
    bad "${override} exists; fresh-resolution evidence cannot be trusted while an override is present"
  else
    echo "  absent (correct): ${override}"
  fi
done
[[ ${fail} -eq 0 ]] || exit 1

# Build a standalone copy of the member: same manifest, minus the workspace
# resolution, so `dart pub get` resolves against the registry exactly as an
# external consumer would rather than against this repo's workspace.
echo '→ resolving the member standalone against the registry'
mkdir -p "${work}/proof"
yq 'del(.resolution) | del(.dev_dependencies)' "${member_pubspec}" >"${work}/proof/pubspec.yaml"
mkdir -p "${work}/proof/lib"
cp -R "${member_dir}/lib/." "${work}/proof/lib/"

if ! (cd "${work}/proof" && dart pub get --no-precompile >"${work}/pubget.log" 2>&1); then
  echo "❌ clean-workspace 'dart pub get' FAILED — the published manifest is not resolvable by a consumer" >&2
  sed 's/^/     /' "${work}/pubget.log" >&2
  exit 1
fi
echo "  clean resolution succeeded"

lock="${work}/proof/pubspec.lock"
[[ -f ${lock} ]] || {
  echo "❌ no pubspec.lock was produced; there is nothing to prove resolution against" >&2
  exit 1
}

# Ask pub's own solver for the newest version admitted by each declared
# constraint. Comparing directly with the registry's global `latest` is wrong:
# a valid `^1.0.0` resolution must not turn red merely because 2.0.0 exists.
# `--show-all` is load-bearing — without it an already-current dependency is
# omitted from the JSON, making the healthy case indistinguishable from a
# missing solver result.
outdated="${work}/outdated.json"
if ! (cd "${work}/proof" &&
  dart pub outdated --json --show-all --no-dev-dependencies >"${outdated}" 2>"${work}/outdated.log"); then
  echo "❌ 'dart pub outdated' FAILED — newest-satisfying versions are unproven" >&2
  sed 's/^/     /' "${work}/outdated.log" >&2
  exit 1
fi

# Every dependency must come from the HOSTED source. ------------------------
echo '→ every resolved dependency is hosted (no path, no git, no sdk)'
# Built with string CONCATENATION, not yq-go's "\(…)" interpolation: on an empty
# selection the interpolation form still emits a stray "=", so an all-hosted
# lockfile would report a phantom non-hosted entry. Concat yields a true empty.
non_hosted="$(yq -r '[.packages | to_entries[] | select(.value.source != "hosted") | .key + "=" + .value.source] | join(",")' "${lock}")"
printf '  non-hosted resolved packages = %s\n' "${non_hosted:-<none>}"
[[ -z ${non_hosted} ]] || bad "resolution pulled non-hosted sources: ${non_hosted}"

total_resolved="$(yq -r '.packages | length' "${lock}")"
printf '  total resolved packages = %s\n' "${total_resolved}"
[[ ${total_resolved} -gt 0 ]] || bad 'the lockfile resolved zero packages; this proves nothing'

# Declared vs freshly resolved vs registry latest. ---------------------------
echo '→ declared constraint / resolved version / solver newest-satisfying / registry latest'
mapfile -t deps < <(yq -r '.dependencies | keys | .[]' "${member_pubspec}")
printf '  hosted dependencies declared = %s\n' "${#deps[@]}"
[[ ${#deps[@]} -gt 0 ]] || bad 'no dependencies declared; nothing to resolve'

for dep in "${deps[@]}"; do
  declared="$(yq -r ".dependencies.${dep}" "${member_pubspec}")"
  resolved="$(yq -r ".packages.${dep}.version // \"ABSENT\"" "${lock}")"

  solver_rows="$(jq --arg dep "${dep}" '[.packages[] | select(.package == $dep and .kind == "direct")] | length' "${outdated}")"
  resolvable="$(jq -r --arg dep "${dep}" '[.packages[] | select(.package == $dep and .kind == "direct")][0].resolvable.version // "ABSENT"' "${outdated}")"
  solver_current="$(jq -r --arg dep "${dep}" '[.packages[] | select(.package == $dep and .kind == "direct")][0].current.version // "ABSENT"' "${outdated}")"
  solver_latest="$(jq -r --arg dep "${dep}" '[.packages[] | select(.package == $dep and .kind == "direct")][0].latest.version // "ABSENT"' "${outdated}")"

  if ! curl -fsSL -H 'Accept: application/vnd.pub.v2+json' \
    "${registry}/api/packages/${dep}" >"${work}/${dep}.json" 2>/dev/null; then
    bad "${dep}: registry query to ${registry} FAILED; refusing to claim freshness without it"
    continue
  fi
  registry_latest="$(yq -r '.latest.version' "${work}/${dep}.json")"

  printf '  %-18s declared=%-10s resolved=%-10s newest-satisfying=%-10s registry-latest=%s\n' \
    "${dep}" "${declared}" "${resolved}" "${resolvable}" "${registry_latest}"

  [[ ${resolved} != 'ABSENT' ]] || {
    bad "${dep} is declared but absent from the fresh lockfile"
    continue
  }
  [[ ${solver_rows} -eq 1 ]] || {
    bad "${dep}: expected exactly one direct solver row, found ${solver_rows}"
    continue
  }
  [[ ${resolvable} != 'ABSENT' ]] || {
    bad "${dep}: pub's solver reported no newest-satisfying version"
    continue
  }
  [[ ${solver_current} == "${resolved}" ]] ||
    bad "${dep}: lockfile resolved ${resolved} but pub outdated inspected ${solver_current}"
  [[ ${solver_latest} == "${registry_latest}" ]] ||
    bad "${dep}: pub reports global latest ${solver_latest} but the registry reports ${registry_latest}"

  published="$(yq -r '[.versions[].version] | length' "${work}/${dep}.json" 2>/dev/null || echo 0)"
  [[ ${published} -gt 0 ]] || bad "${dep}: the registry returned no version list; freshness is unproven"

  # This is the actual staleness/retraction control: the fresh lock must equal
  # the newest version PUB'S SOLVER admits under the declared constraint. The
  # registry's global latest remains printed and cross-checked as context, but
  # it is not substituted for constraint solving.
  if [[ ${resolved} != "${resolvable}" ]]; then
    bad "${dep}: fresh resolution produced ${resolved} but the newest version satisfying ${declared} is ${resolvable}"
  fi
done

[[ ${fail} -eq 0 ]] || {
  echo '❌ hosted-resolution evidence FAILED' >&2
  exit 1
}

echo "✅ hosted resolution verified: ${#deps[@]} declared dependencies, ${total_resolved} packages resolved, all hosted, fresh against ${registry}"
