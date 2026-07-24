#!/usr/bin/env bash
# Heavy Garden-local runtime proof. This installs two instances of the same
# LAPRAS profile, each with its own Postgres and boot Secret, against the exact
# Aldehyde image. It verifies live Management API auth, issuer isolation, and
# one-instance teardown without changing the survivor.
set -euo pipefail

[[ ${K3D_ISOLATE_BY_PATH:-} == true ]] || {
  echo '❌ K3D_ISOLATE_BY_PATH=true is mandatory for the Lithium runtime proof' >&2
  exit 1
}

isolation_key="$(printf %s "${PWD}" | sha256sum | cut -c1-8)"
export K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-diene-lithium-runtime-${isolation_key}}"
export K3D_REGISTRY_NAME="${K3D_REGISTRY_NAME:-diene-lithium-runtime-registry-${isolation_key}}"
export K3D_REGISTRY_PORT="${K3D_REGISTRY_PORT:-$((20000 + (16#${isolation_key:0:4} % 10000)))}"
export K3D_HTTP_PORT="${K3D_HTTP_PORT:-$((30000 + (16#${isolation_key:4:4} % 10000)))}"
export K3D_OWNER_ID="${K3D_OWNER_ID:-lithium-runtime-${isolation_key}-$$}"

tmp="$(mktemp -d)"
export K3D_OWNERSHIP_MARKER="${tmp}/owner"
context="k3d-${K3D_CLUSTER_NAME}"

cleanup() {
  if [[ -e ${K3D_OWNERSHIP_MARKER} ]]; then
    bash scripts/local/delete-k3d-cluster.sh
  fi
  case "${tmp}" in
  /tmp/*) rm -rf -- "${tmp}" ;;
  *) echo "refusing to remove unexpected temp path: ${tmp}" >&2 ;;
  esac
}
trap cleanup EXIT

image_repository="${LITHIUM_IMAGE_REPOSITORY:-$(yq -r '.image.repository' chart/values.yaml)}"
image_tag="${LITHIUM_IMAGE_TAG:-$(yq -r '.image.tag' chart/values.yaml)}"
image_digest="${LITHIUM_IMAGE_DIGEST:-$(yq -r '.image.digest' chart/values.yaml)}"

if [[ -n ${image_digest} ]]; then
  runtime_image="${image_repository}@${image_digest}"
else
  runtime_image="${image_repository}:${image_tag}"
fi

info() { printf '\033[1;36m==\033[0m %s\n' "$*"; }

install_postgres() {
  local namespace="$1"

  kubectl --context "${context}" -n "${namespace}" create deployment postgres \
    --image=postgres:17-alpine >/dev/null
  kubectl --context "${context}" -n "${namespace}" set env deployment/postgres \
    POSTGRES_PASSWORD=postgres POSTGRES_DB=logto >/dev/null
  kubectl --context "${context}" -n "${namespace}" expose deployment postgres \
    --port=5432 --target-port=5432 >/dev/null
  kubectl --context "${context}" -n "${namespace}" rollout status deployment/postgres \
    --timeout=3m >/dev/null

  for _ in $(seq 1 60); do
    if kubectl --context "${context}" -n "${namespace}" exec deployment/postgres -- \
      pg_isready -U postgres -d logto >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done

  echo "❌ Postgres did not become ready in ${namespace}" >&2
  exit 1
}

install_instance() {
  local instance="$1"
  local uid="$2"
  local namespace="lithium-${instance}"
  local client_id="operator-${instance}"
  local client_secret="secret-${instance}"

  kubectl --context "${context}" create namespace "${namespace}" >/dev/null
  install_postgres "${namespace}"
  kubectl --context "${context}" -n "${namespace}" create secret generic "${instance}-db" \
    --from-literal="DB_URL=postgres://postgres:postgres@postgres.${namespace}.svc.cluster.local:5432/logto" >/dev/null
  kubectl --context "${context}" -n "${namespace}" create secret generic "${instance}-boot" \
    --from-literal="SEED_M2M_CLIENT_ID=${client_id}" \
    --from-literal="SEED_M2M_CLIENT_SECRET=${client_secret}" >/dev/null

  helm upgrade --install lithium chart \
    --kube-context "${context}" \
    --namespace "${namespace}" \
    --values chart/values.lapras.yaml \
    --set-string "namespace.name=${namespace}" \
    --set-string "garden.instance=${instance}" \
    --set-string "garden.instanceUID=${uid}" \
    --set-string "garden.databaseSecret=${instance}-db" \
    --set-string "garden.bootSecret=${instance}-boot" \
    --set-string "image.repository=${image_repository}" \
    --set-string "image.tag=${image_tag}" \
    --set-string "image.digest=${image_digest}" \
    --set-string image.pullPolicy=IfNotPresent >/dev/null

  kubectl --context "${context}" -n "${namespace}" rollout status deployment/lithium-api \
    --timeout=10m >/dev/null
  [[ "$(kubectl --context "${context}" -n "${namespace}" exec deployment/lithium-api \
    -c logto -- id -u)" == 10001 ]]
  [[ "$(kubectl --context "${context}" -n "${namespace}" exec deployment/lithium-api \
    -c logto -- id -g)" == 10001 ]]
}

run_operator_journey() {
  local instance="$1"
  local suffix="$2"
  local namespace="lithium-${instance}"
  local client_id="operator-${instance}"
  local client_secret="secret-${instance}"
  local issuer="https://api.lithium.diene.${instance}.lapras.admin.atomi.cloud/oidc"
  local pod="operator-probe-${suffix}"

  # The labels are the chart's explicit management NetworkPolicy allowlist.
  # shellcheck disable=SC2016 # The probe pod, not this shell, expands its env.
  kubectl --context "${context}" -n "${namespace}" run "${pod}" \
    --image=curlimages/curl:8.10.1 \
    --labels=app.kubernetes.io/name=logto-operator,app.kubernetes.io/part-of=lithium \
    --restart=Never \
    --env="CLIENT_ID=${client_id}" \
    --env="CLIENT_SECRET=${client_secret}" \
    --env="EXPECTED_ISSUER=${issuer}" \
    --command -- sh -ec '
      test -n "${CLIENT_ID}" && test -n "${CLIENT_SECRET}" && test -n "${EXPECTED_ISSUER}"
      token_json="$(curl --retry 30 --retry-connrefused --retry-delay 1 -fsS \
        -X POST http://lithium-management/oidc/token \
        -u "${CLIENT_ID}:${CLIENT_SECRET}" \
        --data-urlencode grant_type=client_credentials \
        --data-urlencode resource=https://default.logto.app/api \
        --data-urlencode scope=all)"
      token="$(printf %s "${token_json}" | sed -n "s/.*\"access_token\":\"\([^\"]*\)\".*/\1/p")"
      test -n "${token}"
      curl --retry 10 --retry-connrefused --retry-delay 1 -fsS \
        -H "Authorization: Bearer ${token}" \
        http://lithium-management/api/applications >/dev/null
      discovery="$(curl --retry 10 --retry-connrefused --retry-delay 1 -fsS \
        http://lithium-management/oidc/.well-known/openid-configuration)"
      printf %s "${discovery}" | grep -F "\"issuer\":\"${EXPECTED_ISSUER}\"" >/dev/null
    ' >/dev/null

  if ! kubectl --context "${context}" -n "${namespace}" wait \
    --for=jsonpath='{.status.phase}'=Succeeded "pod/${pod}" --timeout=4m >/dev/null; then
    kubectl --context "${context}" -n "${namespace}" logs "${pod}" >&2 || true
    exit 1
  fi
}

run_public_denial() {
  local instance="$1"
  local namespace="lithium-${instance}"

  # shellcheck disable=SC2016 # The probe pod expands command substitutions.
  kubectl --context "${context}" -n "${namespace}" run public-probe \
    --image=curlimages/curl:8.10.1 \
    --labels=atomi.cloud/rail=ordinary \
    --restart=Never \
    --command -- sh -ec '
      test "$(curl --retry 30 --retry-connrefused --retry-delay 1 -sS \
        -o /dev/null -w "%{http_code}" http://lithium-public/api/applications)" = 404
      curl --retry 10 --retry-connrefused --retry-delay 1 -fsS \
        http://lithium-public/oidc/.well-known/openid-configuration >/dev/null
    ' >/dev/null

  kubectl --context "${context}" -n "${namespace}" wait \
    --for=jsonpath='{.status.phase}'=Succeeded pod/public-probe --timeout=3m >/dev/null
}

info "Create isolated k3d cluster for ${runtime_image}"
bash scripts/local/create-k3d-cluster.sh

if docker image inspect "${runtime_image}" >/dev/null 2>&1; then
  info 'Import the local Aldehyde image into k3d'
  k3d image import "${runtime_image}" --cluster "${K3D_CLUSTER_NAME}" >/dev/null
fi

info 'Install two independent instances of the same LAPRAS profile'
install_instance lapras-001 00000000-0000-0000-0000-000000000001
install_instance lapras-002 00000000-0000-0000-0000-000000000002

run_operator_journey lapras-001 initial
run_operator_journey lapras-002 initial
run_public_denial lapras-001
run_public_denial lapras-002

[[ "$(kubectl --context "${context}" -n lithium-lapras-001 get secret lapras-001-db \
  -o jsonpath='{.data.DB_URL}')" != "$(kubectl --context "${context}" -n lithium-lapras-002 \
    get secret lapras-002-db -o jsonpath='{.data.DB_URL}')" ]] || {
  echo '❌ the two instances unexpectedly share a database URL' >&2
  exit 1
}

info 'Tear down one complete instance and re-check the survivor'
helm uninstall lithium --kube-context "${context}" --namespace lithium-lapras-001 >/dev/null
kubectl --context "${context}" delete namespace lithium-lapras-001 --wait=true >/dev/null
kubectl --context "${context}" -n lithium-lapras-002 rollout status deployment/lithium-api \
  --timeout=3m >/dev/null
run_operator_journey lapras-002 after-teardown

kubectl --context "${context}" get namespace lithium-lapras-001 >/dev/null 2>&1 && {
  echo '❌ torn-down instance namespace still exists' >&2
  exit 1
}

echo "✅ Lithium two-instance Garden runtime and teardown proof passed for ${runtime_image}"
