#!/usr/bin/env bash
set -euo pipefail

echo "🔎 checking operator layer imports"

module="$(go list -m)"
if [[ -z ${module} ]]; then
  echo "❌ operator architecture: go.mod declares no main module path" >&2
  exit 1
fi
echo "📦 module import root: ${module}"

controllers_dir="adapters/operator/controllers"
if [[ ! -d ${controllers_dir} ]] || [[ ! -r ${controllers_dir} ]]; then
  echo "❌ operator architecture: unreadable controllers directory ${controllers_dir}" >&2
  exit 1
fi

shopt -s nullglob
all_go=("${controllers_dir}"/*.go)
controller_files=()
reconciler_files=()
for path in "${all_go[@]}"; do
  [[ ${path} == *_test.go ]] && continue
  controller_files+=("${path}")
  [[ ${path##*/} == "conditions.go" ]] && continue
  reconciler_files+=("${path}")
done
shopt -u nullglob

if [[ ${#controller_files[@]} -eq 0 ]]; then
  echo "❌ operator architecture: no non-test controller package files found" >&2
  exit 1
fi

echo "🧮 discovered controller files: ${#controller_files[@]}; reconcilers: ${#reconciler_files[@]}"
for path in "${controller_files[@]}"; do
  echo "🔎 checked controller path: ${path}"
done

if [[ ${#reconciler_files[@]} -eq 0 ]]; then
  if [[ ${#controller_files[@]} -ne 1 ]] || [[ ${controller_files[0]##*/} != "conditions.go" ]]; then
    echo "❌ operator architecture: zero reconcilers require exactly the conditions.go package sentinel" >&2
    exit 1
  fi
  echo "PASS: no reconcilers in the Phase-2 foundation window"
else
  approved_decision_imports=("${module}/lib/operator/lifecycle")
  for path in "${reconciler_files[@]}"; do
    approved=0
    for decision_import in "${approved_decision_imports[@]}"; do
      if rg -q -F "\"${decision_import}\"" "${path}"; then
        approved=1
      fi
    done
    if [[ ${approved} -ne 1 ]]; then
      echo "❌ operator architecture: ${path} imports no approved pure decision package" >&2
      exit 1
    fi

    while IFS= read -r domain_import; do
      [[ -z ${domain_import} ]] && continue
      allowed=0
      for decision_import in "${approved_decision_imports[@]}"; do
        [[ ${domain_import} == "${decision_import}" ]] && allowed=1
      done
      if [[ ${allowed} -ne 1 ]]; then
        echo "❌ operator architecture: ${path} imports unapproved decision package ${domain_import}" >&2
        exit 1
      fi
    done < <(sed -nE "s|^.*\"(${module//./\\.}/lib/operator/[^\"]+)\".*|\\1|p" "${path}")
  done
fi

if k8s_in_domain="$(rg -n '"(k8s\.io|sigs\.k8s\.io)/' lib/operator)"; then
  printf '%s\n' "${k8s_in_domain}" >&2
  echo "❌ operator architecture: lib/operator must remain Kubernetes-free" >&2
  exit 1
fi

echo "🧪 asserting the AST thin-controller boundary"
go run ./tools/archcheck

echo "✅ operator architecture boundary passed"
