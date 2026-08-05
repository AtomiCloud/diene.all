#!/usr/bin/env bash
set -euo pipefail

# PRE-VENDOR HOOK.
#
# skills-sync vendors each dependency's skills out of the package manager's own
# on-disk cache, so it can only see packages that have already been materialised
# there. On a runner whose shared cache holds only SOME of the declared
# skill-bearing packages it publishes a PARTIAL vendor tree, and the freshness
# gate then fails three steps later on a diff that says nothing about the cause.
#
# The contract: before skills are vendored, each ecosystem gets one chance to
# materialise its declared packages. An ecosystem that takes it makes the vendor
# tree a function of the declared dependency set instead of ambient cache state.
# An ecosystem that does not may get a partial vendor tree and a misleading
# freshness diff.
#
# This template is ecosystem-neutral and declares no packages of its own, so it
# ships no hook and the block below does nothing here. A downstream node supplies
# one by adding an executable at this path — a .NET node runs `dotnet restore`,
# a Node node its install, and so on. See docs/standards/ci-cd/index.md.
#
# Three states, three outcomes. The hook is optional, so absent is a normal
# successful setup; but "present and unusable" is a misconfiguration and gets its
# own refusal rather than being folded into the absent case. Wrapping the
# executability check inside the existence check is what turns that into a silent
# skip, and a silently skipped restore is the exact failure this hook exists to
# prevent.
pre_vendor="./scripts/ci/pre-vendor.sh"
if [ -e "${pre_vendor}" ]; then
  [ -x "${pre_vendor}" ] || {
    echo "❌ '${pre_vendor}' exists but is not executable — the pre-vendor hook cannot run," >&2
    echo "   so the vendor tree below would be built from whatever the cache happens to hold." >&2
    echo "   Run: chmod +x ${pre_vendor}" >&2
    exit 1
  }
  echo "🔧 Materialising declared packages before vendoring their skills..."
  rc=0
  "${pre_vendor}" || rc=$?
  [ "${rc}" = "0" ] || {
    echo "❌ pre-vendor hook '${pre_vendor}' failed (exit ${rc}) — refusing to vendor skills." >&2
    echo "   Vendoring now would publish a partial tree and the skills-freshness gate would" >&2
    echo "   then fail on a diff that does not name this as the cause." >&2
    exit "${rc}"
  }
fi

./scripts/local/skills-sync.sh

echo "✅ Repository setup complete"
