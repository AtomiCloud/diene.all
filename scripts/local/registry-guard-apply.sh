#!/usr/bin/env bash
set -euo pipefail

# Idempotent apply of the fleet `registry/**` guard (Q-GH1 posture).
#
# Provisions the `main` branch ruleset from
# .github/rulesets/registry-guard-main.json against a PUBLIC fleet repo. The
# ruleset requires a PR + a code-owner review before merge, and exempts the
# Kargo bot (Always bypass) so its `platforms/**` promotion pushes land
# directly. CODEOWNERS (.github/CODEOWNERS) assigns `registry/**` to the
# fleet-admin team; the ruleset's require_code_owner_review turns that into a
# hard fleet-admin gate on registry changes.
#
# Human-run and idempotent: re-running converges to the same state, so it also
# serves as the drift repair for `scripts/validate/registry-guard.sh`.
#
# Required env:
#   FLEET_REPO            owner/repo of the fleet repository (e.g. AtomiCloud/fleet)
#   KARGO_BOT_ACTOR_ID    numeric actor id of the Kargo bot (GitHub App or user)
#   KARGO_BOT_ACTOR_TYPE  Integration | OrganizationAdmin | RepositoryRole | Team

repo="${FLEET_REPO:?set FLEET_REPO to owner/repo of the fleet repository}"
: "${KARGO_BOT_ACTOR_ID:?set KARGO_BOT_ACTOR_ID to the Kargo bot actor id}"
: "${KARGO_BOT_ACTOR_TYPE:?set KARGO_BOT_ACTOR_TYPE (e.g. Integration)}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
template="${here}/.github/rulesets/registry-guard-main.json"
codeowners="${here}/.github/CODEOWNERS"

[ ! -s "${template}" ] && echo "❌ ruleset payload ${template} missing" >&2 && exit 1
[ ! -s "${codeowners}" ] && echo "❌ CODEOWNERS ${codeowners} missing" >&2 && exit 1

# The single-quoted variable list is envsubst's allow-list, not shell expansion.
# shellcheck disable=SC2016
payload="$(KARGO_BOT_ACTOR_ID="${KARGO_BOT_ACTOR_ID}" KARGO_BOT_ACTOR_TYPE="${KARGO_BOT_ACTOR_TYPE}" \
  envsubst '${KARGO_BOT_ACTOR_ID} ${KARGO_BOT_ACTOR_TYPE}' <"${template}")"
name="$(jq -r '.name' <<<"${payload}")"

existing_id="$(gh api "repos/${repo}/rulesets" --jq ".[] | select(.name == \"${name}\") | .id" 2>/dev/null || true)"

if [ -n "${existing_id}" ]; then
  echo "↻ updating existing ruleset ${name} (id ${existing_id}) on ${repo}"
  printf '%s' "${payload}" | gh api -X PUT "repos/${repo}/rulesets/${existing_id}" --input - >/dev/null
else
  echo "＋ creating ruleset ${name} on ${repo}"
  printf '%s' "${payload}" | gh api -X POST "repos/${repo}/rulesets" --input - >/dev/null
fi

echo "✅ registry guard applied to ${repo} (ruleset ${name} + CODEOWNERS present)"
