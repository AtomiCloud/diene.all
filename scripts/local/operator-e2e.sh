#!/usr/bin/env bash
set -euo pipefail

# Reusable lapras/k3d end-to-end harness. Create a throwaway cluster, build and
# import the manager image, stand up a MinIO ledger backend, install the chart,
# apply a toy Note, wait for it to converge to Ready, assert its owned resources,
# then tear everything down. All four dogfood consumers reuse this harness for
# their own e2e (parameterize CHART/VALUES/FIXTURE for their CRDs).
#
# Parameters (env overrides):
#   CLUSTER   k3d cluster name   (default: operator-template-e2e)
#   CHART     chart path         (default: infra/root_chart)
#   VALUES    values file        (default: infra/root_chart/values.lapras.yaml)
#   FIXTURE   Note CR fixture     (default: tests/fixtures/operator/valid-note.yaml)
#   IMAGE     manager image ref   (default: operator-template:e2e)
#   TIMEOUT   readiness timeout   (default: 180s)

CLUSTER="${CLUSTER:-operator-template-e2e}"
CHART="${CHART:-infra/root_chart}"
VALUES="${VALUES:-infra/root_chart/values.lapras.yaml}"
FIXTURE="${FIXTURE:-tests/fixtures/operator/valid-note.yaml}"
IMAGE="${IMAGE:-operator-template:e2e}"
TIMEOUT="${TIMEOUT:-180s}"
NAMESPACE="${NAMESPACE:-operator-template}"

cleanup() {
  k3d cluster delete "${CLUSTER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "▶ creating k3d cluster ${CLUSTER}"
k3d cluster create "${CLUSTER}" --wait --timeout "${TIMEOUT}"

echo "▶ building manager image ${IMAGE}"
docker build -f infra/Dockerfile -t "${IMAGE}" .

echo "▶ importing image into ${CLUSTER}"
k3d image import "${IMAGE}" -c "${CLUSTER}"

kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

echo "▶ deploying MinIO ledger backend"
kubectl apply -n "${NAMESPACE}" -f - <<'MINIO'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
spec:
  replicas: 1
  selector:
    matchLabels: { app: minio }
  template:
    metadata:
      labels: { app: minio }
    spec:
      containers:
        - name: minio
          image: minio/minio:RELEASE.2024-01-16T16-07-38Z
          args: ["server", "/data"]
          env:
            - { name: MINIO_ROOT_USER, value: minioadmin }
            - { name: MINIO_ROOT_PASSWORD, value: minioadmin }
          ports:
            - containerPort: 9000
---
apiVersion: v1
kind: Service
metadata:
  name: minio
spec:
  selector: { app: minio }
  ports:
    - port: 9000
      targetPort: 9000
MINIO
kubectl rollout status -n "${NAMESPACE}" deploy/minio --timeout "${TIMEOUT}"

echo "▶ creating ledger secret"
kubectl create secret generic operator-template-ledger -n "${NAMESPACE}" \
  --from-literal=accessKey=minioadmin \
  --from-literal=secretKey=minioadmin \
  --dry-run=client -o yaml | kubectl apply -f -

echo "▶ installing manager chart"
helm install operator-template "${CHART}" \
  -n "${NAMESPACE}" \
  -f "${VALUES}" \
  --set image.repository="${IMAGE%%:*}" \
  --set image.tag="${IMAGE##*:}" \
  --set image.pullPolicy=IfNotPresent \
  --set serviceMonitor.enabled=false \
  --set alerts.enabled=false \
  --set dashboard.enabled=false \
  --set ledger.endpoint=minio:9000 \
  --set ledger.secure=false \
  --wait --timeout "${TIMEOUT}"

echo "▶ applying toy Note"
kubectl apply -n "${NAMESPACE}" -f "${FIXTURE}"

echo "▶ waiting for Note to converge to Ready"
kubectl wait -n "${NAMESPACE}" --for=condition=Ready --timeout "${TIMEOUT}" note/harness-note

echo "▶ asserting owned ConfigMaps"
copies="$(kubectl get configmaps -n "${NAMESPACE}" \
  -l operator-template.diene.atomi.cloud/note=harness-note \
  --no-headers 2>/dev/null | wc -l)"
[ "${copies}" -eq 2 ] || {
  echo "❌ expected 2 owned ConfigMaps, found ${copies}" >&2
  exit 1
}

echo "✅ operator k3d e2e journey passed (${copies} owned copies, Note Ready)"
