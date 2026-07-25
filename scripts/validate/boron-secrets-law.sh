#!/usr/bin/env bash
set -euo pipefail

# Secrets law (goals/charts/boron.md): the Cloudflare API token is consumed ONLY
# through the platform SecretStore chain — no inline/static token field may
# exist anywhere in the CRD schema or chart values surface.

echo "🔎 asserting no inline/literal credential field in the API schema"

# 1. No spec field whose JSON name looks like a literal token/credential value.
#    apiTokenSecretRef is the ONLY token-adjacent field and it is a reference.
bad_fields="$(grep -rnE 'json:"(apiToken|token|apiKey|secret|password|credential)[",]' api/v1alpha1/*_types.go || true)"
[ -n "${bad_fields}" ] && echo "${bad_fields}" >&2 && echo "❌ secrets law: a literal credential field exists in the CRD schema (only apiTokenSecretRef is lawful)" >&2 && exit 1

# 2. The generated CRDs carry no plaintext token property either.
bad_crd="$(grep -rniE '^\s+(apiToken|token|apiKey|password):' infra/root_chart/templates/crds/*.yaml | grep -v 'SecretRef' || true)"
[ -n "${bad_crd}" ] && echo "${bad_crd}" >&2 && echo "❌ secrets law: generated CRD exposes a literal credential property" >&2 && exit 1

# 3. Chart values carry no token value surface.
bad_values="$(grep -rniE '(apiToken|cfToken|cloudflareToken|api_key|apiKey):' infra/root_chart/values*.yaml || true)"
[ -n "${bad_values}" ] && echo "${bad_values}" >&2 && echo "❌ secrets law: chart values expose a credential field" >&2 && exit 1

# 4. Source never reads a token from an env var or hardcodes one; the only
#    ingestion path is the Secret named by apiTokenSecretRef.
bad_env="$(grep -rnE 'Getenv\("(CF_|CLOUDFLARE_)?(API_)?TOKEN' cmd internal adapters lib || true)"
[ -n "${bad_env}" ] && echo "${bad_env}" >&2 && echo "❌ secrets law: source ingests a token from the environment instead of the SecretStore chain" >&2 && exit 1

echo "✅ boron secrets law passed (SecretStore chain only, no inline token)"
