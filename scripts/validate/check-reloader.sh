#!/usr/bin/env bash
# ### chlorine-check-reloader
# #### source: chlorine
#
# Reusable Reloader annotation opt-in checker. Reads a rendered manifest and
# asserts the Reloader Deployment stays annotation OPT-IN: the container args
# carry --reload-strategy=annotations and never carry --auto-reload-all=true.
# Exit-code predicate: 0 = opt-in, 1 = drift, so a sabotaged render
# (autoReloadAll=true, or a non-annotation strategy) reddens it. The positive
# `reloader` mode and the negative `reloader-violation` mode invoke the SAME
# checker so the negative proves the enforcement path actually catches regression.
set -euo pipefail

rendered="${1:?usage: check-reloader.sh <rendered.yaml>}"

yq eval-all -o=json '.' "${rendered}" |
  jq -se '
    map(select(.kind == "Deployment"))
      | (length == 1)
        and ((.[0].spec.template.spec.containers[0].args // [])
          | (any(. == "--auto-reload-all=true") | not)
            and (any(. == "--reload-strategy=annotations")))' >/dev/null
