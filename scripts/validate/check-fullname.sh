#!/usr/bin/env bash
# ### chlorine-check-fullname
# #### source: chlorine
#
# Reusable fullname-conformance checker. The helm-wrapper contract requires every
# CONTROLLABLE rendered name to be the exactly-one-dash `<service>-<token>` form
# (`chlorine-reloader`), set via fullnameOverride. For this chart the controllable
# surface is the Deployment AND the ServiceAccount; both must equal that name and
# match ^[a-z0-9]+-[a-z0-9]+$.
#
# Documented upstream exception (Xenon RB-fullname-scope precedent): the vendored
# Reloader subchart appends fixed RBAC suffixes to the fullname on its
# ClusterRole/ClusterRoleBinding/Role/RoleBinding (`-role`, `-role-binding`,
# `-metadata-role`, `-metadata-role-binding`). Those names are not one-dash and
# are not freely controllable, so the checker binds each to
# fullname-plus-known-suffix instead — a fullname drift is still caught there, but
# the upstream suffix itself is an accepted exception rather than silently treated
# as conformant.
#
# Exit-code predicate: 0 = conformant, 1 = drift. A sabotaged render (a second
# dash in fullnameOverride, a chart-default fullname, or a drifted controllable
# name such as an overridden serviceAccount.name) reddens it. The positive
# `fullname` mode and the negative `fullname-violation` / `fullname-sa-violation`
# modes invoke the SAME checker so the negatives prove the enforcement path
# actually catches regression across the full controllable surface.
set -euo pipefail

rendered="${1:?usage: check-fullname.sh <rendered.yaml>}"
fullname="chlorine-reloader"

yq eval-all -o=json '.' "${rendered}" |
  jq -se --arg fn "${fullname}" '
    # Controllable names: exactly one Deployment and one ServiceAccount, each the
    # exactly-one-dash <service>-<token> fullname.
    (map(select(.kind == "Deployment")) | length == 1)
    and (map(select(.kind == "ServiceAccount")) | length == 1)
    and (map(select(.kind == "Deployment" or .kind == "ServiceAccount"))
      | map(.metadata.name == $fn and (.metadata.name | test("^[a-z0-9]+-[a-z0-9]+$")))
      | all)
    # Upstream RBAC exception: names are bound to fullname + known suffix so a
    # fullname drift is still caught, without demanding one-dash conformance.
    and (map(select(.kind == "ClusterRole"))        | map(.metadata.name == ($fn + "-role"))                  | all)
    and (map(select(.kind == "ClusterRoleBinding")) | map(.metadata.name == ($fn + "-role-binding"))          | all)
    and (map(select(.kind == "Role"))               | map(.metadata.name == ($fn + "-metadata-role"))         | all)
    and (map(select(.kind == "RoleBinding"))        | map(.metadata.name == ($fn + "-metadata-role-binding")) | all)' >/dev/null
