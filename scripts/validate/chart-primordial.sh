#!/usr/bin/env bash
set -euo pipefail

# The primordial chart gate (R20). Bound to `infra/primordial_chart/` by the
# `a-chart-primordial` pre-commit hook, so the chart is re-checked on every change
# to it rather than validated once by hand.
#
# `helm lint` reads `values.schema.json` itself, so this one entry covers BOTH
# owed gate rows — lint AND schema. Proven: a `labelPrefix: 12345` type violation
# turns lint rc=1 with "at '/labelPrefix': got number, want string".

chart="infra/primordial_chart"

[ -d "${chart}" ] || {
  echo "❌ '${chart}' is missing: the E4 primordial chart (R20) must exist" >&2
  exit 1
}

# Fail closed if the toolchain is absent, so "could not look" never reads as
# "found nothing". kubernetes-helm is in nix/packages.nix and both dev shells.
command -v helm >/dev/null 2>&1 || {
  echo "❌ 'helm' is not on PATH: the chart gate cannot verify anything" >&2
  exit 1
}

echo "📝 Chart: $(helm show chart "${chart}" | yq -N -r '.name + " " + .version')"

echo "🔨 helm lint (values.schema.json is enforced here)..."
helm lint "${chart}" --strict

# Render, then assert on the KINDS produced. Asserting on `helm template`'s exit
# code alone would pass on an empty render — the command succeeding is not the
# subject being present.
echo "🔨 helm template..."
rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT INT TERM
helm template chart-gate "${chart}" --namespace platform >"${rendered}"

kinds="$(yq -N -r 'select(.kind != null) | .kind' "${rendered}" | sort -u | paste -sd, -)"
echo "📝 Rendered kinds: ${kinds:-<none>}"

# The two resources this node's live mechanisms REQUIRE. GrafanaDashboard and
# GrafanaAlertRuleGroup are deliberately NOT asserted: their templates ship and
# are proven to render, but this node's dashboard/alert CONTENT is owed
# (infra/primordial_chart/README.md). Asserting them would make the gate red for
# a documented, deliberate absence.
for kind in GrafanaFolder LogtoApp; do
  printf '%s\n' "${kinds}" | tr ',' '\n' | grep -qx "${kind}" || {
    echo "❌ '${kind}' did not render; the chart declares a mechanism it no longer emits" >&2
    exit 1
  }
done

# The LogtoApp must carry a redeemable callback. A native client whose callback
# set is empty registers an app nothing can redirect into: login then fails in
# the installed binary, long after the chart went green.
callbacks="$(yq -N -r 'select(.kind == "LogtoApp") | .spec.extraRedirectUris // [] | length' "${rendered}")"
echo "📝 LogtoApp callbacks registered: ${callbacks}"
[ "${callbacks}" -lt 1 ] && echo "❌ the LogtoApp registers no redirect URI a native client could redeem" >&2 && exit 1

echo "✅ primordial chart lints, validates against its schema, and renders ${kinds}"
