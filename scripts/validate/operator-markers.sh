#!/usr/bin/env bash
set -euo pipefail

# Marker-lint gate: assert the required kubebuilder marker families are present.
# No existing linter enforces marker PRESENCE (controller-gen silently emits an
# unvalidated CRD when markers are absent), so this is a small custom gate.

fail() {
  echo "❌ operator marker lint: $1" >&2
  exit 1
}

types_dir="api/v1alpha1"

# Every root Kind must carry a status subresource and at least one print column.
for file in "${types_dir}"/*_types.go; do
  if grep -q "kubebuilder:object:root=true" "${file}"; then
    grep -q "kubebuilder:subresource:status" "${file}" ||
      fail "${file}: missing +kubebuilder:subresource:status marker"
    grep -q "kubebuilder:printcolumn" "${file}" ||
      fail "${file}: missing +kubebuilder:printcolumn marker"
  fi
done

# Spec fields must carry validation markers.
grep -rq "kubebuilder:validation:" "${types_dir}" ||
  fail "no +kubebuilder:validation markers found under ${types_dir}"

# Controllers must declare their RBAC via markers.
grep -rq "kubebuilder:rbac:" adapters/operator/controllers ||
  fail "no +kubebuilder:rbac markers found under adapters/operator/controllers"

echo "✅ operator marker lint passed"
