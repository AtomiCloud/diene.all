#!/usr/bin/env bash
# ### chlorine-check-labels
# #### source: chlorine
#
# Reusable LPSM label/annotation conformance checker. Reads a rendered manifest
# and asserts the primary Deployment carries the canonical chlorine service-tree
# identity: the six <prefix>/{platform,service,module,layer,landscape,cluster}
# labels plus the namespace-sourced platform and the reversible instance
# annotations. This is an exit-code predicate (no progress echo): 0 = conformant,
# 1 = drift, so a sabotaged render (a wrong service value, a dropped key, a
# namespace/platform mismatch) reddens it. The positive `labels` mode and the
# negative `labels-violation` mode invoke the SAME checker so the negative
# proves the enforcement path actually catches regression.
set -euo pipefail

rendered="${1:?usage: check-labels.sh <rendered.yaml> [expected-namespace]}"
namespace="${2:-sample}"

# Six LPSM labels on the Deployment object metadata; platform == release namespace.
yq eval-all -o=json '.' "${rendered}" |
  jq --arg ns "${namespace}" -se '
    map(select(.kind == "Deployment"))
      | (length == 1)
        and (.[0].metadata.labels
          | (.["atomi.cloud/platform"] == $ns)
            and (.["atomi.cloud/service"] == "chlorine")
            and (.["atomi.cloud/module"] == "reloader")
            and (.["atomi.cloud/layer"] == "1")
            and (.["atomi.cloud/landscape"] == "example")
            and (.["atomi.cloud/cluster"] == "lapras"))' >/dev/null

# Pod-template annotations: service-tree projection + reversible instance metadata.
yq eval-all -o=json '.' "${rendered}" |
  jq --arg ns "${namespace}" -se '
    map(select(.kind == "Deployment"))
      | (length == 1)
        and (.[0].spec.template.metadata.annotations
          | (.["atomi.cloud/platform"] == $ns)
            and (.["atomi.cloud/service"] == "chlorine")
            and (.["atomi.cloud/module"] == "reloader")
            and (.["atomi.cloud/layer"] == "1")
            and (.["atomi.cloud/landscape"] == "example")
            and (.["atomi.cloud/cluster"] == "lapras")
            and (.["atomi.cloud/instance-original"] == "diene-chlorine:run-001")
            and (.["atomi.cloud/instance-label"] == "diene-chlorine-run-001"))' >/dev/null
