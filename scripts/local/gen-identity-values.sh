#!/usr/bin/env bash
# Derive the cert-manager subchart identity labels from the single labelPrefix
# input and the serviceTree projection, emitting an upstream.global.commonLabels
# values layer on stdout.
#
# Subchart values cannot call templates, so sulfur cannot stamp the LPSM identity
# labels onto the cert-manager resources from its own helpers. This generator is
# therefore the ONE supported rendering path: it turns the single configurable
# labelPrefix (plus the serviceTree projection) into the commonLabels keys the
# subchart applies. Every template/install command must render with the emitted
# layer appended so labelPrefix genuinely drives the rendered labels — there is
# no static, independently editable mirror to drift.
#
# Usage:
#   gen-identity-values.sh [values-overlay.yaml ...] > identity.yaml
# The base chart/values.yaml is always merged first, then each overlay in order,
# so landscape/cluster slots added by overlays flow into the derived labels.
set -euo pipefail

# The single-quoted $-tokens below are yq expression variables, not shell.
# shellcheck disable=SC2016
yq eval-all '. as $item ireduce ({}; . * $item)' chart/values.yaml "$@" |
  yq '
    .labelPrefix as $prefix
    | (.serviceTree // {})
    | to_entries
    | (.[] as $entry ireduce ({}; . * {($prefix + "/" + $entry.key): ($entry.value | tostring)}))
    | {"upstream": {"global": {"commonLabels": .}}}
  '
