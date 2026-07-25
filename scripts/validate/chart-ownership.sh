#!/usr/bin/env bash
set -euo pipefail

# The Garden app chart owns a Deployment, a ClusterIP Service, and an optional
# ServiceAccount — nothing else. Edge, DNS, and TLS belong to Garden's
# exposure-compile action, which is what keeps ONE chart valid across a Boron
# landscape, a loopback landscape, and a hosted vcluster without branching.
#
# The values schema already makes a hosted-Boron or public-callback DECLARATION
# unrepresentable. This guard covers the other direction: a template author
# adding a host-side object directly, where no value is involved at all.

chart="infra/garden_app_chart"
allowed="Deployment|Service|ServiceAccount"
forbidden="Gateway|ListenerSet|HTTPRoute|GRPCRoute|TCPRoute|TLSRoute|ReferenceGrant|Certificate|CertificateRequest|Issuer|ClusterIssuer|Ingress|IngressClass|Secret|ConfigMap"

for profile in "${chart}"/profiles/*.yaml; do
  name="$(basename "${profile}" .yaml)"
  [ "${name}" = "rejected-hosted-boron" ] && continue

  rendered="$(helm template ownership-check "${chart}" -f "${profile}")"

  while IFS= read -r kind; do
    [ -z "${kind}" ] && continue
    if echo "${kind}" | grep -qE "^(${forbidden})$"; then
      echo "❌ ${name}: chart renders forbidden host-side object '${kind}'" >&2
      echo "   Edge, DNS, and TLS belong to Garden's exposure-compile action." >&2
      exit 1
    fi
    if ! echo "${kind}" | grep -qE "^(${allowed})$"; then
      echo "❌ ${name}: chart renders unowned object '${kind}'" >&2
      echo "   The app chart owns only: ${allowed//|/, }." >&2
      exit 1
    fi
  done < <(echo "${rendered}" | grep '^kind:' | sed 's/^kind:[[:space:]]*//')

  echo "${rendered}" | grep -q '^kind: Deployment$' || {
    echo "❌ ${name}: no Deployment rendered" >&2
    exit 1
  }
  echo "${rendered}" | grep -q '^kind: Service$' || {
    echo "❌ ${name}: no Service rendered" >&2
    exit 1
  }
  echo "${rendered}" | grep -qE '^\s+type: ClusterIP$' || {
    echo "❌ ${name}: Service is not ClusterIP" >&2
    exit 1
  }
done

echo "✅ Garden app chart owns only its workload objects across every profile"
