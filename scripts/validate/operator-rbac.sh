#!/usr/bin/env bash
set -euo pipefail

committed="infra/root_chart/templates/rbac/role.yaml"
if [[ ! -f ${committed} ]]; then
  echo "❌ operator RBAC: missing committed ClusterRole at ${committed}" >&2
  exit 1
fi

tmp="$(mktemp -d)"
cleanup() {
  rm -rf -- "${tmp}"
}
trap cleanup EXIT

echo "🔎 proving the zero-marker RBAC baseline"

set +e
controller-gen rbac:roleName=fleet-operator-manager \
  paths=./adapters/operator/controllers/... output:rbac:dir="${tmp}/raw"
raw_rc=$?
set -e
if [[ ${raw_rc} -ne 0 ]]; then
  echo "❌ operator RBAC: raw controller-gen failed with rc ${raw_rc}" >&2
  exit "${raw_rc}"
fi

if [[ -f "${tmp}/raw/role.yaml" ]]; then
  if ! cmp -s "${committed}" "${tmp}/raw/role.yaml"; then
    diff -u "${committed}" "${tmp}/raw/role.yaml" >&2
    echo "❌ operator RBAC: unexpected raw output differs from the committed ClusterRole" >&2
    exit 1
  fi
  echo "❌ operator RBAC: raw controller-gen unexpectedly emitted a role in the zero-marker window" >&2
  exit 1
fi
if [[ -d "${tmp}/raw" ]] && [[ -n "$(find "${tmp}/raw" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "❌ operator RBAC: raw controller-gen emitted an unexpected artifact" >&2
  exit 1
fi

canonical="${tmp}/canonical-role.yaml"
cat >"${canonical}" <<'EOF'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: fleet-operator-manager
rules: []
EOF

if ! cmp -s "${committed}" "${canonical}"; then
  diff -u "${canonical}" "${committed}" >&2
  echo "❌ operator RBAC: committed ClusterRole differs from the canonical zero-grant fallback" >&2
  exit 1
fi

rules_json="$(yq -o=json -I=0 '.rules' "${committed}")"
if [[ ${rules_json} != "[]" ]]; then
  echo "❌ operator RBAC: rules must be exactly []" >&2
  exit 1
fi
rule_count="$(yq -r '.rules | length' "${committed}")"
# shellcheck disable=SC2016 # yq expression, not shell interpolation.
grant_count="$(yq -r '[.rules[] | select(.resources != null) | .apiGroups[] as $g | .resources[] as $r | .verbs[] as $v | $g + "|" + $r + "|" + $v] | length' "${committed}")"
# shellcheck disable=SC2016 # yq expression, not shell interpolation.
nonresource_count="$(yq -r '[.rules[] | select(.nonResourceURLs != null) | .nonResourceURLs[]] | length' "${committed}")"
if [[ ${rule_count} -ne 0 ]] || [[ ${grant_count} -ne 0 ]]; then
  echo "❌ operator RBAC: expected zero rules/grants, got rules=${rule_count} grants=${grant_count}" >&2
  exit 1
fi
if [[ ${nonresource_count} -ne 0 ]]; then
  echo "❌ operator RBAC: manager ClusterRole must not hold nonResourceURLs grants" >&2
  exit 1
fi

retired_group="sample"".""diene.atomi.cloud"
if rg -n -F "${retired_group}" "${committed}"; then
  echo "❌ operator RBAC: retired API group remains in the committed ClusterRole" >&2
  exit 1
fi

role_blob="$(git hash-object "${committed}")"
if [[ ${role_blob} != "030f84bdd074e4320cdbda38e166273deed3f7b6" ]]; then
  echo "❌ operator RBAC: canonical fallback blob changed: ${role_blob}" >&2
  exit 1
fi

echo "🧮 raw role files: 0; committed rules: ${rule_count}; grants: ${grant_count}; non-resource grants: ${nonresource_count}"
echo "✅ operator RBAC exact zero-grant census passed"
