#!/usr/bin/env bash
# Q-G22 sequential-minor upgrade gate (enforced by this chart repo's OWN CI).
# The pinned cert-manager minor may advance by at most one minor from the
# recorded previousMinor; skipping a minor (or downgrading, or changing major)
# reddens. The CRD upgrade path follows the same rule. The negative fixture in
# scripts/validate/sulfur.sh injects a skipped minor through SEQ_PINNED_MINOR.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
policy="${repo_root}/chart/upgrade-policy.yaml"
[ ! -s "${policy}" ] && echo "❌ upgrade policy ${policy} is missing" >&2 && exit 1

chart_version="$(yq -r '.dependencies[] | select(.name == "cert-manager") | .version' "${repo_root}/chart/Chart.yaml")"
chart_minor="$(printf '%s' "${chart_version#v}" | awk -F. '{print $1"."$2}')"
policy_pinned="$(yq -r '.pinnedMinor' "${policy}")"
policy_previous="$(yq -r '.previousMinor' "${policy}")"
crd_path="$(yq -r '.crdUpgradePath' "${policy}")"

pinned="${SEQ_PINNED_MINOR:-${chart_minor}}"
previous="${SEQ_PREVIOUS_MINOR:-${policy_previous}}"

# The declared policy must stay consistent with the actually pinned chart minor.
if [ -z "${SEQ_PINNED_MINOR:-}" ] && [ "${policy_pinned}" != "${chart_minor}" ]; then
  echo "❌ upgrade-policy pinnedMinor ${policy_pinned} does not match Chart.yaml cert-manager minor ${chart_minor}" >&2
  exit 1
fi
[ "${crd_path}" != "sequential-minor" ] && echo "❌ CRD upgrade path must be sequential-minor, got '${crd_path}'" >&2 && exit 1

pinned_major="${pinned%.*}"
pinned_minor="${pinned#*.}"
prev_major="${previous%.*}"
prev_minor="${previous#*.}"

[ "${pinned_major}" != "${prev_major}" ] && echo "❌ major version change ${previous} -> ${pinned} is not a sequential-minor bump" >&2 && exit 1
delta=$((pinned_minor - prev_minor))
[ "${delta}" -lt 0 ] && echo "❌ downgrade ${previous} -> ${pinned} is not allowed" >&2 && exit 1
[ "${delta}" -gt 1 ] && echo "❌ version-skip: ${previous} -> ${pinned} skips a cert-manager minor (sequential-minor only)" >&2 && exit 1

echo "✅ sequential-minor upgrade gate: ${previous} -> ${pinned} (delta ${delta}); CRD path ${crd_path}"
