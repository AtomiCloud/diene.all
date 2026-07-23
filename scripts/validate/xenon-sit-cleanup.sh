#!/usr/bin/env bash
# Ownership-safe cleanup invoked by xenon-sit.sh's EXIT trap.
set -euo pipefail

context="${SIT_CONTEXT:-}"
namespace="${SIT_NAMESPACE:-}"
release="${RELEASE:-}"
evidence_dir="${SIT_EVIDENCE_DIR:-}"

[ -z "${context}" ] && echo "❌ cleanup SIT_CONTEXT is required" >&2 && exit 1
[ -z "${namespace}" ] && echo "❌ cleanup SIT_NAMESPACE is required" >&2 && exit 1
[ -z "${release}" ] && echo "❌ cleanup RELEASE is required" >&2 && exit 1
[ -z "${evidence_dir}" ] && echo "❌ cleanup SIT_EVIDENCE_DIR is required" >&2 && exit 1
[ ! -d "${evidence_dir}" ] && echo "❌ cleanup evidence directory does not exist" >&2 && exit 1

if [ ! -s "${evidence_dir}/ownership.claim" ]; then
  printf '%s\n' 'skipped-no-ownership-claim' >"${evidence_dir}/cleanup.status"
  exit 0
fi

if ! claim="$(jq -ce '
  select(
    (.context | type == "string" and length > 0)
    and (.namespace | type == "string" and length > 0)
    and (.release | type == "string" and length > 0)
    and (.runId | type == "string" and test("^xenon-sit-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"))
    and (.ownershipLabel.key | type == "string" and endswith("/sit-run-id"))
    and (.ownershipLabel.value == .runId)
  )
' "${evidence_dir}/ownership.claim")"; then
  printf '%s\n' 'failed-invalid-ownership-claim' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup ownership claim is invalid; leaving the release untouched" >&2
  exit 1
fi

claim_context="$(printf '%s' "${claim}" | jq -r '.context')"
claim_namespace="$(printf '%s' "${claim}" | jq -r '.namespace')"
claim_release="$(printf '%s' "${claim}" | jq -r '.release')"
run_id="$(printf '%s' "${claim}" | jq -r '.runId')"
ownership_label_key="$(printf '%s' "${claim}" | jq -r '.ownershipLabel.key')"
if [ "${claim_context}" != "${context}" ] || [ "${claim_namespace}" != "${namespace}" ] || [ "${claim_release}" != "${release}" ]; then
  printf '%s\n' 'failed-ownership-claim-scope' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup ownership claim does not match the requested release scope; leaving the release untouched" >&2
  exit 1
fi

if ! helm list --all --kube-context "${context}" --namespace "${namespace}" --filter "^${release}$" --output json \
  > >(tee "${evidence_dir}/cleanup-list.stdout.json") \
  2> >(tee "${evidence_dir}/cleanup-list.stderr" >&2); then
  printf '%s\n' 'failed-list' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup could not inspect release ownership" >&2
  exit 1
fi

if ! release_count="$(jq -er 'length' "${evidence_dir}/cleanup-list.stdout.json")"; then
  printf '%s\n' 'failed-list-output' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup received invalid release-list evidence; leaving the release untouched" >&2
  exit 1
fi
if [ "${release_count}" -eq 0 ]; then
  printf '%s\n' 'already-absent' >"${evidence_dir}/cleanup.status"
  exit 0
fi
[ "${release_count}" -ne 1 ] && printf '%s\n' 'failed-ambiguous-release' >"${evidence_dir}/cleanup.status" && echo "❌ cleanup found ${release_count} matching releases" >&2 && exit 1
if ! jq -e --arg release "${release}" 'length == 1 and .[0].name == $release' "${evidence_dir}/cleanup-list.stdout.json" >/dev/null; then
  printf '%s\n' 'failed-ambiguous-release' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup release listing did not contain the exact claimed name; leaving it untouched" >&2
  exit 1
fi

if ! helm list --all --kube-context "${context}" --namespace "${namespace}" --filter "^${release}$" \
  --selector "${ownership_label_key}=${run_id}" --output json \
  > >(tee "${evidence_dir}/cleanup-owner.stdout.json") \
  2> >(tee "${evidence_dir}/cleanup-owner.stderr" >&2); then
  printf '%s\n' 'failed-owner-check' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup could not verify the run-specific release owner; leaving the release untouched" >&2
  exit 1
fi
if ! jq -e --arg release "${release}" 'length == 1 and .[0].name == $release' "${evidence_dir}/cleanup-owner.stdout.json" >/dev/null; then
  printf '%s\n' 'failed-owner-mismatch' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup found a same-name release without the claimed run ID; leaving it untouched" >&2
  exit 1
fi

if ! helm uninstall "${release}" --kube-context "${context}" --namespace "${namespace}" --wait --timeout 5m \
  > >(tee "${evidence_dir}/cleanup-uninstall.stdout") \
  2> >(tee "${evidence_dir}/cleanup-uninstall.stderr" >&2); then
  printf '%s\n' 'failed-uninstall' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup failed to uninstall ${release}; inspect cleanup-uninstall.stderr" >&2
  exit 1
fi

if ! helm list --all --kube-context "${context}" --namespace "${namespace}" --filter "^${release}$" --output json \
  > >(tee "${evidence_dir}/cleanup-verify.stdout.json") \
  2> >(tee "${evidence_dir}/cleanup-verify.stderr" >&2); then
  printf '%s\n' 'failed-verify' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup could not verify release removal" >&2
  exit 1
fi
if ! jq -e 'length == 0' "${evidence_dir}/cleanup-verify.stdout.json" >/dev/null; then
  printf '%s\n' 'failed-verify-present' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup verification found the release still present" >&2
  exit 1
fi
printf '%s\n' 'uninstalled' >"${evidence_dir}/cleanup.status"

echo "✅ Xenon SIT release cleanup completed"
