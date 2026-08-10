#!/usr/bin/env bash
# Sourceable helper for scripts/local/operator-e2e.sh.
#
# Derives shared-resource names for one harness invocation. Consumers may pin a
# stable cluster or image by exporting a non-empty override; that value is used
# verbatim. Defaults share one unique invocation ID so parallel probe sandboxes
# never collide on k3d or Docker names (PROBES.md §5 uniqueness addendum).
# shellcheck shell=bash

# e2e_invocation_id SEED ENTROPY
#   SEED     stable per-worktree entropy (e.g. the sandbox path)
#   ENTROPY  per-invocation entropy (e.g. the shell PID)
e2e_invocation_id() {
  local digest
  digest="$(printf '%s:%s' "${1:-}" "${2:-}" | sha256sum | cut -c1-16)"
  printf '%s' "${digest}"
}

# e2e_cluster_name OVERRIDE INVOCATION_ID
# Emits a lowercase RFC1123 name well within k3d's 32-character limit.
e2e_cluster_name() {
  local override="${1:-}"
  [ -n "${override}" ] && printf '%s' "${override}" && return 0
  printf 'operator-e2e-%s' "${2:-}"
}

# e2e_image_name OVERRIDE INVOCATION_ID
e2e_image_name() {
  local override="${1:-}"
  [ -n "${override}" ] && printf '%s' "${override}" && return 0
  printf 'operator-template:e2e-%s' "${2:-}"
}
