#!/usr/bin/env bash
set -euo pipefail

compose="scripts/local/docker-compose.yaml"
control="scripts/sit-control/server.ts"
rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT

required_services=(
  upstash-lapras
  upstash-farfetch
  mercury-lapras
  mercury-farfetch
  mercury-dbinit
  mercury-tls
  sit-control
)
for service in "${required_services[@]}"; do
  rg -q "^  ${service}:$" "${compose}" || {
    echo "❌ SIT compose is missing ${service}" >&2
    exit 1
  }
done

[[ $(rg -c '^  mercury-dbinit:$' "${compose}") -eq 1 ]] || {
  echo "❌ db-init must be defined exactly once" >&2
  exit 1
}
rg -q 'redis://upstash-lapras:6379' "${compose}"
rg -q 'redis://upstash-farfetch:6379' "${compose}"
rg -q 'MERCURY_SIT_PUBLIC_ORIGIN' scripts/ci/sit.sh scripts/sit-control/write-config.ts
rg -q 'MERCURY_TLS_PORT' scripts/ci/sit.sh scripts/local/test-sit.sh "${compose}"
rg -q 'MERCURY_SIT_RUN_ID' scripts/ci/sit.sh scripts/local/up.sh scripts/local/down.sh
rg -q 'COMPOSE_PROJECT_NAME.*must uniquely identify' scripts/ci/sit-stack.sh
rg -q 'trap cleanup EXIT' scripts/ci/sit.sh
rg -q 'cleanup_failed_start' scripts/local/up.sh
rg -q 'NODE_EXTRA_CA_CERTS' scripts/ci/sit.sh scripts/local/test-sit.sh "${compose}"
rg -q 'MERCURY_SIT_CONTROL_BEARER' scripts/ci/sit.sh scripts/local/test-sit.sh "${compose}"
rg -q 'providers/apple-app-store-history\.p8' scripts/sit-control/write-material.ts
rg -q 'providers/google-pubsub-service-account\.json' scripts/sit-control/write-material.ts
rg -q 'signingKeySecretRef: apple-app-store-history\.p8' scripts/sit-control/write-config.ts
rg -q 'credentialSecretRef: google-pubsub-service-account\.json' scripts/sit-control/write-config.ts

for scenario in \
  dependencies \
  provider-verification \
  atomic-acceptance \
  fanout \
  signature-lifecycle \
  console-journey \
  apple-backfill \
  google-subscription \
  archive-lifecycle \
  route53-landing; do
  rg -Fq "${scenario}" "${control}" || {
    echo "❌ v1 SIT control is missing ${scenario}" >&2
    exit 1
  }
done
rg -q 'MERCURY_SIT_PROOF_TRUST_JSON' "${compose}" scripts/sit-control/attestation.ts
rg -q 'asymmetricKeyType.*ed25519' scripts/sit-control/attestation.ts
rg -q 'requestDigest' scripts/sit-control/attestation.ts
rg -q 'nonce' scripts/sit-control/attestation.ts "${control}"
if rg -n 'MERCURY_SIT_.*_PROOF_URL|proofResource|proxied' \
  scripts/sit-control scripts/local scripts/ci/sit.sh scripts/ci/sit-stack.sh; then
  echo "❌ arbitrary scenario proof URLs are forbidden" >&2
  exit 1
fi

if rg -n --glob '!scripts/validate/sit-contracts.sh' \
  'NODE_TLS_REJECT_UNAUTHORIZED|rejectUnauthorized:\s*false|--no-check-certificate' \
  scripts infra/garden .github/workflows; then
  echo "❌ SIT TLS verification must never be disabled" >&2
  exit 1
fi

helm template mercury infra/root_chart >"${rendered}"
for name in \
  MERCURY_SECURITY__CONSOLE_SESSION_SECRET_FILE \
  MERCURY_SECURITY__MANAGEMENT_BOOTSTRAP_TOKEN_FILE \
  MERCURY_SECURITY__PROVIDER_SECRET_ROOT \
  MERCURY_SECURITY__ENDPOINT_SECRET_ROOT \
  MERCURY_SECURITY__ARCHIVE_ACCESS_KEY_ID_FILE \
  MERCURY_SECURITY__ARCHIVE_SECRET_ACCESS_KEY_FILE \
  MERCURY_SECURITY__CONSOLE_AUTHORIZATION_PRIVATE_KEY_FILE \
  MERCURY_SECURITY__CONSOLE_AUTHORIZATION_PUBLIC_KEY_FILE; do
  rg -q "name: ${name}" "${rendered}" || {
    echo "❌ chart is missing ${name}" >&2
    exit 1
  }
done
rg -q 'mountPath: /var/run/secrets/mercury/providers' "${rendered}"
rg -q 'mountPath: /var/run/secrets/mercury/endpoints' "${rendered}"
rg -q 'secretName: webhook-hooks-providers' "${rendered}"
rg -q 'secretName: webhook-hooks-endpoints' "${rendered}"
echo "✅ Two-landscape SIT, TLS, control protocol, and secret projections are wired"
