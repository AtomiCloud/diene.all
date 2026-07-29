#!/usr/bin/env bash
set -euo pipefail

rg -q "chart_path: ./infra/root_chart" .github/workflows/cd.yaml
rg -q "chart_path: ./infra/primordial_chart" .github/workflows/cd.yaml
rg -q "image_name: atomicloud/diene.mercury" .github/workflows/cd.yaml
rg -q "name: webhook-canary" infra/kargo/promotion-contract.yaml
rg -q "name: webhook-active" infra/kargo/promotion-contract.yaml
rg -q 'stages: \[webhook-canary\]' infra/kargo/promotion-contract.yaml
rg -q "freightCreationCriteria:" infra/kargo/promotion-contract.yaml
rg -q "name: Release Black-Box Proof" .github/workflows/cd.yaml
rg -q 'needs: \[sit\]' .github/workflows/cd.yaml

# Pre-publication barrier: every artifact of a semver must build/scan/package before
# any of them is published, so a version can never be published as a partial subset.
rg -q '^  preflight-image:' .github/workflows/cd.yaml
rg -q '^  preflight-app-chart:' .github/workflows/cd.yaml
rg -q '^  preflight-primordial-chart:' .github/workflows/cd.yaml
if ! rg -qF 'needs: [preflight-image, preflight-app-chart, preflight-primordial-chart]' .github/workflows/cd.yaml; then
  echo "❌ image and chart publication must be gated behind the full pre-publication barrier" >&2
  exit 1
fi
publish_gated="$(rg -cF 'needs: [preflight-image, preflight-app-chart, preflight-primordial-chart]' .github/workflows/cd.yaml)"
if [ "${publish_gated}" -ne 3 ]; then
  echo "❌ expected all three publish jobs behind the barrier, found ${publish_gated}" >&2
  exit 1
fi

# Final immutable-set verification: partial publication (missing image platform or a
# missing chart) must fail the release; registry pushes are not transactional.
if ! yq -o=json .github/workflows/cd.yaml | jq -e '
  .jobs.verify.name == "Verify Immutable Release Set" and
  .jobs.verify.needs == ["image", "app-chart", "primordial-chart"] and
  .jobs.verify.uses == "./.github/workflows/⚡reusable-release-verify.yaml" and
  .jobs.verify.secrets == "inherit" and
  .jobs.verify.with.version == "${{ github.ref_name }}"
' >/dev/null; then
  echo "❌ CD immutable-set verification must call the gated local reusable workflow" >&2
  exit 1
fi
if ! yq -o=json .github/workflows/⚡reusable-release-verify.yaml | jq -e '
  .jobs.verify.permissions.contents == "read" and
  .jobs.verify.permissions.packages == "read" and
  .jobs.verify.env.DOMAIN == "ghcr.io" and
  (.jobs.verify.steps | any(.run == "nix develop .#cd -c ./scripts/ci/release-verify.sh"))
' >/dev/null; then
  echo "❌ reusable release verification must run the exact read-only script wiring" >&2
  exit 1
fi
if rg -q 'skopeo inspect|missing required platform|partial publication detected' \
  .github/workflows/cd.yaml .github/workflows/⚡reusable-release-verify.yaml; then
  echo "❌ immutable-set verification must live in scripts/ci/release-verify.sh" >&2
  exit 1
fi
[ -x scripts/ci/release-verify.sh ] || {
  echo "❌ scripts/ci/release-verify.sh must be executable" >&2
  exit 1
}
rg -qF 'version="${RELEASE_VERSION#v}"' scripts/ci/release-verify.sh
rg -qF 'image="ghcr.io/atomicloud/diene.mercury:${version}"' scripts/ci/release-verify.sh
rg -qF 'app="${DOMAIN}/${normalized_owner}/mercury-webhook:${version}"' scripts/ci/release-verify.sh
rg -qF 'primordial="${DOMAIN}/${normalized_owner}/mercury-webhook-primordial:${version}"' scripts/ci/release-verify.sh
rg -qF 'for want in linux/amd64 linux/arm64; do' scripts/ci/release-verify.sh
rg -qF 'partial publication detected' scripts/ci/release-verify.sh
rg -qF 'for name in DOMAIN DOCKER_USER DOCKER_PASSWORD OWNER RELEASE_VERSION; do' scripts/ci/release-verify.sh || {
  echo "❌ release verification must fail closed when any required input is absent" >&2
  exit 1
}

# Container publication must scan every target platform BEFORE any registry push, from
# immutable local artifacts, never a runner-architecture-only post-push tag scan.
rg -q "for platform in" scripts/ci/docker.sh
scan_line="$(rg -n -- '--input' scripts/ci/docker.sh | head -1 | cut -d: -f1)"
push_line="$(rg -n -- '--push' scripts/ci/docker.sh | head -1 | cut -d: -f1)"
if [ -z "${scan_line}" ] || [ -z "${push_line}" ] || [ "${scan_line}" -ge "${push_line}" ]; then
  echo "❌ docker.sh must scan every platform artifact before any registry push" >&2
  exit 1
fi

if rg -n --ignore-case --glob '!scripts/validate/release-rails.sh' '\b(kubectl apply|helm (install|upgrade)|argocd app|kargo promote)\b' Taskfile.yaml tasks scripts .github/workflows; then
  echo "❌ direct deployment command found; promotion must remain Kargo-owned" >&2
  exit 1
fi
if find . -maxdepth 2 \( -type d -name probes -o -type f -name features.json \) | rg -q .; then
  echo "❌ materialized Mercury must not ship probes/ or features.json" >&2
  exit 1
fi
echo "✅ Release rails publish only and hand promotion to Kargo"
