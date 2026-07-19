#!/usr/bin/env bash
set -euo pipefail

# sulfur cert-manager engine — unit-tier CI validation (S30 / Q-I27).
# Runs the full unit pyramid: schema, render, static conformance, the inherited
# Q-G20 rendered-manifest stage, the Q-G22 sequential-minor gate, and the
# sulfur contract negative fixtures. The k3d integration tier is separate.

bash ./scripts/ci/setup.sh
bash ./scripts/validate/sulfur.sh schema
bash ./scripts/validate/sulfur.sh schema-drift
bash ./scripts/validate/sulfur.sh lint
bash ./scripts/validate/sulfur.sh render
bash ./scripts/validate/sulfur.sh labels
bash ./scripts/validate/sulfur.sh identity
bash ./scripts/validate/sulfur.sh reloader
bash ./scripts/validate/sulfur.sh rendered-manifests
bash ./scripts/validate/sulfur.sh sequential-minor
# Q-G22 strict gate: derive the base cert-manager pin from the PR/push base and
# turn a minor-skipping version-bump PR red (not just validate semver).
bash ./scripts/validate/sequential-minor.sh --ci-gate chart
bash ./scripts/validate/sulfur.sh gateway-api
bash ./scripts/validate/sulfur.sh no-dead-flag
bash ./scripts/validate/sulfur.sh no-issuer
bash ./scripts/validate/sulfur.sh crds
bash ./scripts/validate/sulfur.sh publish-git
bash ./scripts/validate/sulfur.sh publish-oci
bash ./scripts/validate/sulfur.sh version
bash ./scripts/validate/sulfur.sh presence
bash ./scripts/validate/gitlint-types.sh

echo "✅ sulfur CI validation complete"
