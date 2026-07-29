#!/usr/bin/env bash
set -euo pipefail

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

helm lint infra/root_chart
helm lint infra/primordial_chart
helm template mercury infra/root_chart >"${tmp}/app.yaml"
helm template mercury-primordial infra/primordial_chart >"${tmp}/primordial.yaml"
helm template mercury-lapras infra/root_chart -f infra/root_chart/values.lapras.yaml >"${tmp}/app-lapras.yaml"
helm template mercury-lapras-primordial infra/primordial_chart -f infra/primordial_chart/values.lapras.yaml >"${tmp}/primordial-lapras.yaml"

for kind in Deployment Service Job NetworkPolicy ExternalSecret PodDisruptionBudget HorizontalPodAutoscaler ServiceMonitor PrometheusRule; do
  rg -q "^kind: ${kind}$" "${tmp}/app.yaml" || {
    echo "❌ app chart is missing ${kind}" >&2
    exit 1
  }
done
for kind in VirtualLandscapeService PlatformDependency WebhookEngine; do
  rg -q "^kind: ${kind}$" "${tmp}/primordial.yaml" || {
    echo "❌ primordial chart is missing ${kind}" >&2
    exit 1
  }
done
rg -q '^kind: WebhookRoute$' "${tmp}/primordial.yaml" && echo "❌ consumer WebhookRoute fragments must not be emitted" >&2 && exit 1
rg -q 'type: neon' "${tmp}/primordial.yaml"
rg -q 'type: upstash' "${tmp}/primordial.yaml"
rg -q 'type: tigris' "${tmp}/primordial.yaml"
rg -q 'type: dragonfly' "${tmp}/primordial-lapras.yaml"
rg -q 'snapshot: true' "${tmp}/primordial-lapras.yaml"
rg -q 'mountPath: /var/run/secrets/mercury/providers' "${tmp}/app.yaml"
rg -q 'mountPath: /var/run/secrets/mercury/endpoints' "${tmp}/app.yaml"
rg -q 'property: MANAGEMENT_BOOTSTRAP_TOKEN' "${tmp}/app.yaml"
rg -q 'property: TIGRIS_ACCESS_KEY_ID' "${tmp}/app.yaml"
rg -q 'property: CONSOLE_AUTHORIZATION_PRIVATE_KEY' "${tmp}/app.yaml"

# Every secretKeyRef the pods consume must have a rendered ExternalSecret
# producer, so a Secret is never referenced with a key nothing materializes
# (CreateContainerConfigError). Checked across the default and lapras renders.
secret_parity="$(
  cat <<'PARITY'
import { readFileSync } from 'node:fs';
import { parseAllDocuments } from 'yaml';

const manifests = process.env.MANIFESTS.split(':').filter(Boolean);
const consumers = new Map();
const producers = new Set();
const SEP = '::';

const walk = (node, path) => {
  if (Array.isArray(node)) {
    for (const item of node) walk(item, path);
    return;
  }
  if (node === null || typeof node !== 'object') return;
  const ref = node.secretKeyRef;
  if (ref && typeof ref === 'object' && typeof ref.name === 'string' && typeof ref.key === 'string') {
    consumers.set(`${ref.name}${SEP}${ref.key}`, path);
  }
  for (const value of Object.values(node)) walk(value, path);
};

for (const manifest of manifests) {
  const docs = parseAllDocuments(readFileSync(manifest, 'utf8'))
    .map((doc) => doc.toJS())
    .filter(Boolean);
  for (const doc of docs) {
    if (doc.kind === 'ExternalSecret') {
      const target = doc.spec?.target?.name;
      const data = doc.spec?.data;
      if (typeof target === 'string' && Array.isArray(data)) {
        for (const entry of data) {
          if (entry && typeof entry.secretKey === 'string') producers.add(`${target}${SEP}${entry.secretKey}`);
        }
      }
    }
    walk(doc, manifest);
  }
}

const missing = [...consumers.keys()].filter((key) => !producers.has(key));
if (missing.length > 0) {
  console.error('❌ secretKeyRef consumers without a rendered ExternalSecret producer:');
  for (const key of missing) {
    const [name, secretKey] = key.split(SEP);
    console.error(`   Secret ${name} key ${secretKey}`);
  }
  process.exit(1);
}
console.log(`✅ secret producer/consumer parity (${consumers.size} secretKeyRef consumers produced)`);
PARITY
)"
MANIFESTS="${tmp}/app.yaml:${tmp}/app-lapras.yaml" bun -e "${secret_parity}"

# Every required storage connection key is produced and consumed.
for key in redis-url postgres-url archive-endpoint archive-bucket archive-region; do
  rg -q "secretKey: ${key}$" "${tmp}/app.yaml" || {
    echo "❌ ExternalSecret does not produce storage key ${key}" >&2
    exit 1
  }
  rg -q "key: ${key}$" "${tmp}/app.yaml" || {
    echo "❌ no secretKeyRef consumer for storage key ${key}" >&2
    exit 1
  }
done

# NetworkPolicy must be default-deny yet permit DNS, cluster-local HTTP
# delivery, and platform-approved external dependency/destination egress.
rg -q 'policyTypes: \[Ingress, Egress\]' "${tmp}/app.yaml" || {
  echo "❌ NetworkPolicy is not default-deny on both directions" >&2
  exit 1
}
rg -q 'port: 53' "${tmp}/app.yaml" || { echo "❌ NetworkPolicy omits DNS egress" >&2 && exit 1; }
rg -q 'port: 8080' "${tmp}/app.yaml" || { echo "❌ NetworkPolicy omits cluster-local HTTP delivery egress" >&2 && exit 1; }
rg -q 'cidr: 0.0.0.0/0' "${tmp}/app.yaml" || { echo "❌ NetworkPolicy omits platform-approved external egress" >&2 && exit 1; }

# No rendered NetworkPolicy rule may use an empty all-namespace selector: an
# `{}` namespaceSelector grants lateral access to pods in every namespace.
# Checked across the default and lapras renders.
for manifest in "${tmp}/app.yaml" "${tmp}/app-lapras.yaml"; do
  if rg -q 'namespaceSelector:\s*\{\s*\}' "${manifest}"; then
    echo "❌ NetworkPolicy renders an empty all-namespace selector in $(basename "${manifest}")" >&2
    exit 1
  fi
done

# Cluster-local delivery must render an explicit trusted-topology destination:
# a non-empty namespace selector AND an explicit pod selector, so tenant data
# can never widen it to all namespaces.
rg -q 'atomi.cloud/webhook-delivery: allowed' "${tmp}/app.yaml" || {
  echo "❌ NetworkPolicy cluster-local delivery is missing its explicit namespace selector" >&2
  exit 1
}
# The webhook-endpoint label only ever appears inside the delivery destination's
# pod selector, so its presence proves destinations are pod-scoped (not a bare
# namespace rule).
rg -q 'atomi.cloud/webhook-endpoint:' "${tmp}/app.yaml" || {
  echo "❌ NetworkPolicy cluster-local delivery is missing its explicit pod selector" >&2
  exit 1
}

# Apple missed-cycle observability rule ships in the app chart.
rg -q 'alert: MercuryAppleBackfillMissedCycles' "${tmp}/app.yaml" || {
  echo "❌ app chart is missing the Apple missed-cycle PrometheusRule" >&2
  exit 1
}
rg -q 'mercury_apple_backfill_missed_cycles.* > 2' "${tmp}/app.yaml" || {
  echo "❌ Apple missed-cycle alert does not fire above two missed cycles" >&2
  exit 1
}

sha256sum "${tmp}/app.yaml" "${tmp}/primordial.yaml" | sed "s#${tmp}/##" >"${tmp}/snapshots.sha256"
diff -u infra/chart-snapshots.sha256 "${tmp}/snapshots.sha256"
echo "✅ Chart contracts and deterministic snapshots passed"
