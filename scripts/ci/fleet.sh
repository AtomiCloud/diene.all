#!/usr/bin/env bash
set -euo pipefail

# Fleet node CI batch. Ordinary chart + product gates (S30 — no probe matrix).
# Live SIT/e2e traces (throwaway ArgoCD / sandbox repo / k3d) are deferred and
# documented in docs/domain/fleet-repo.md.

bash ./scripts/validate/fleet.sh lint
bash ./scripts/validate/fleet.sh input-schema
bash ./scripts/validate/fleet.sh schema-drift
bash ./scripts/validate/fleet.sh render
bash ./scripts/validate/fleet.sh row-identity
bash ./scripts/validate/fleet.sh golden
bash ./scripts/validate/fleet.sh golden-mutation
bash ./scripts/validate/fleet.sh canary-features
bash ./scripts/validate/fleet.sh dag
bash ./scripts/validate/fleet.sh delivery-mode
bash ./scripts/validate/fleet.sh freight-alignment
bash ./scripts/validate/fleet.sh kargo-values-preservation
bash ./scripts/validate/fleet.sh kargo-row-update-contract
(
  cd ./scripts/validate/kargo-yaml-update
  GOTOOLCHAIN=local go test -count=1 ./...
)
bash ./scripts/validate/fleet.sh row-values-persistence
bash ./scripts/validate/fleet.sh registry-cr
bash ./scripts/validate/fleet.sh webhook-secret
bash ./scripts/validate/fleet.sh rendered-cr
bash ./scripts/validate/fleet.sh cloudflare-rollout-negative
bash ./scripts/validate/fleet.sh webhookengine-version-negative
bash ./scripts/validate/fleet.sh appset-scope
bash ./scripts/validate/fleet.sh row-expansion
bash ./scripts/validate/fleet.sh platforms-appset
bash ./scripts/validate/fleet.sh machinery-pin
bash ./scripts/validate/fleet.sh guard
bash ./scripts/validate/fleet.sh presence

echo "✅ fleet CI validation complete"
