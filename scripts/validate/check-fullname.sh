#!/usr/bin/env bash
# ### chlorine-check-fullname
# #### source: chlorine
#
# Reusable fullname-conformance checker. Reads a rendered manifest and asserts
# the primary Deployment name is the exactly-one-dash `<service>-<token>` form
# (`chlorine-reloader`): it equals the expected token and matches
# ^[a-z0-9]+-[a-z0-9]+$. Exit-code predicate: 0 = conformant, 1 = drift, so a
# sabotaged render (a second dash in fullnameOverride, or a chart-default
# fullname) reddens it. The positive `fullname` mode and the negative
# `fullname-violation` mode invoke the SAME checker so the negative proves the
# enforcement path actually catches regression.
set -euo pipefail

rendered="${1:?usage: check-fullname.sh <rendered.yaml>}"

yq eval-all -o=json '.' "${rendered}" |
  jq -se '
    map(select(.kind == "Deployment"))
      | (length == 1)
        and (.[0].metadata.name
          | (. == "chlorine-reloader")
            and (test("^[a-z0-9]+-[a-z0-9]+$")))' >/dev/null
