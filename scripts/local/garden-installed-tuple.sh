#!/usr/bin/env bash
set -euo pipefail

profile="${1:-}"
namespaces="${DIENE_INSTALLED_NAMESPACES:---all-namespaces}"
pods_json="${DIENE_PODS_JSON:-}"

[ -z "${profile}" ] && echo "❌ profile not set; usage: garden-installed-tuple.sh <profile>" >&2 && exit 1

raw="$(mktemp)"
trap 'rm -f "${raw}"' EXIT

# Installed digests come from what the kubelet actually resolved, never from the manifest
# tag: imageID carries the digest the node really pulled.
if [ -n "${pods_json}" ]; then
  [ ! -s "${pods_json}" ] && echo "❌ pod inventory '${pods_json}' not found or empty" >&2 && exit 1
  cp "${pods_json}" "${raw}"
else
  # shellcheck disable=SC2086
  kubectl get pods ${namespaces} -o json >"${raw}"
fi

jq -e '.items != null' "${raw}" >/dev/null || {
  echo "❌ pod inventory is not a Kubernetes list" >&2
  exit 1
}

# A member owns a pod when the pod carries its service-tree label; that is the same
# projection the charts already stamp, so no second mapping table is invented here.
jq --arg profile "${profile}" '
  {($profile): (
    [ .items[]
      | (.metadata.labels["atomi.cloud/service"] // empty) as $member
      | { member: $member,
          digests: [ (.status.containerStatuses // [])[]
                     | .imageID
                     | capture("(?<d>sha256:[0-9a-f]{64})").d ] }
    ]
    | group_by(.member)
    | map({ key: .[0].member, value: { images: (map(.digests) | add | unique) } })
    | from_entries
  )}' "${raw}"
