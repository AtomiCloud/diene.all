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

if ! helm list --all --kube-context "${context}" --namespace "${namespace}" --filter "^${release}$" --output json \
  > >(tee "${evidence_dir}/cleanup-list.stdout.json") \
  2> >(tee "${evidence_dir}/cleanup-list.stderr" >&2); then
  printf '%s\n' 'failed-list' >"${evidence_dir}/cleanup.status"
  echo "❌ cleanup could not inspect release ownership" >&2
  exit 1
fi

release_count="$(jq 'length' "${evidence_dir}/cleanup-list.stdout.json")"
if [ "${release_count}" -eq 0 ]; then
  printf '%s\n' 'already-absent' >"${evidence_dir}/cleanup.status"
  exit 0
fi
[ "${release_count}" -ne 1 ] && printf '%s\n' 'failed-ambiguous-release' >"${evidence_dir}/cleanup.status" && echo "❌ cleanup found ${release_count} matching releases" >&2 && exit 1
jq -e --arg release "${release}" 'length == 1 and .[0].name == $release' "${evidence_dir}/cleanup-list.stdout.json" >/dev/null

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
jq -e 'length == 0' "${evidence_dir}/cleanup-verify.stdout.json" >/dev/null
printf '%s\n' 'uninstalled' >"${evidence_dir}/cleanup.status"

echo "✅ Xenon SIT release cleanup completed"
