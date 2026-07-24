#!/usr/bin/env bash
set -euo pipefail

proof="scripts/validate/carbon-k3d.sh"

rg -q 'K3D_ISOLATE_BY_PATH=true is mandatory' "${proof}"
rg -q 'apply -f tests/fixtures/crds' "${proof}"
rg -q 'crd/platformdependencies.fleet.atomi.cloud' "${proof}"
rg -q -- '--namespace feature-carbon-123' "${proof}"
rg -q 'get secretstore carbon-store' "${proof}"
rg -q 'get platformdependency carbon-mew' "${proof}"

apply_line="$(rg -n 'apply -f tests/fixtures/crds' "${proof}" | cut -d: -f1)"
app_line="$(rg -n 'helm upgrade --install carbon chart' "${proof}" | cut -d: -f1)"
primordial_line="$(rg -n 'helm upgrade --install carbon-primordial' "${proof}" | cut -d: -f1)"
assert_line="$(rg -n 'get platformdependency carbon-mew' "${proof}" | cut -d: -f1)"

install_stanza() {
  local start="$1" n=0 line
  local continuation='\\[[:space:]]*$'
  while IFS= read -r line; do
    n=$((n + 1))
    if ((n < start)); then continue; fi
    printf '%s\n' "${line}"
    [[ ${line} =~ ${continuation} ]] || break
  done <"${proof}"
}

app_stanza="$(install_stanza "${app_line}")"
primordial_stanza="$(install_stanza "${primordial_line}")"

rg -q -- '--namespace default([[:space:]]|$)' <<<"${app_stanza}" || {
  echo "❌ app install must use the pre-existing default namespace" >&2
  exit 1
}
if rg -q -- '--create-namespace' <<<"${app_stanza}"; then
  echo "❌ app install must not create the default namespace" >&2
  exit 1
fi
rg -q -- '--create-namespace' <<<"${primordial_stanza}" || {
  echo "❌ primordial install must retain namespace creation" >&2
  exit 1
}

[ "${apply_line}" -lt "${app_line}" ] || {
  echo "❌ CRD fixtures must precede the app install" >&2
  exit 1
}
[ "${app_line}" -lt "${primordial_line}" ] || {
  echo "❌ app install must precede the primordial install" >&2
  exit 1
}
[ "${primordial_line}" -lt "${assert_line}" ] || {
  echo "❌ both installs must precede behavior assertions" >&2
  exit 1
}

for fixture in tests/fixtures/crds/externalsecret.yaml tests/fixtures/crds/secretstore.yaml tests/fixtures/crds/platformdependency.yaml; do
  yq -e '
    .apiVersion == "apiextensions.k8s.io/v1" and
    .kind == "CustomResourceDefinition" and
    (.spec.versions | length == 1) and
    .spec.versions[0].served == true and
    .spec.versions[0].storage == true and
    (.spec.versions[0].schema.openAPIV3Schema.type == "object")
  ' "${fixture}" >/dev/null
done

echo "✅ Carbon k3d integration contract and fixtures passed"
