#!/usr/bin/env bash
set -euo pipefail

# R-E33 — keep the generated changelog formatter-clean AT GENERATION TIME.
#
# semantic-release writes the changelog entry verbatim from
# conventional-changelog-writer, which emits `*` bullets and a double blank line
# after the version heading. prettier rewrites BOTH, treefmt runs with
# --fail-on-change, and `nix flake check` runs the same hook set — so one
# unformatted release commit reddens Pre-Commit AND Nix Flake Check at the
# released commit.
#
# Repairing that afterwards is worse than the defect. The only repair available
# is a commit to the changelog, and atomi_release.yaml maps every obvious commit
# type for it (fix, style, perf, refactor, test) to a release — so the repair
# starts another release, another unformatted entry, and another IRREVERSIBLE
# publish. diene_core_utils reached 1.0.1 exactly that way.
#
# This script runs from the @semantic-release/exec prepare step. The fixed plugin
# chain places exec AFTER @semantic-release/changelog has written the entry and
# BEFORE @semantic-release/git commits the assets, so the bytes that land in the
# release commit are already the bytes the hook set demands.

root_dir="$(git rev-parse --show-toplevel)"
cd "${root_dir}"

changelog="$(yq -r '.plugins[] | select(.module == "@semantic-release/changelog") | .config.changelogFile' atomi_release.yaml)"
[[ -z ${changelog} || ${changelog} == "null" ]] && echo "❌ atomi_release.yaml declares no changelog plugin changelogFile" >&2 && exit 1
[[ ! -f ${changelog} ]] && echo "❌ generated changelog '${changelog}' does not exist" >&2 && exit 1

# Unconditional: the release environment is `nix develop .#releaser`, so nix is
# always present. A missing formatter must go RED here rather than silently skip
# and hand an unformatted file to the git plugin.
command -v nix >/dev/null || {
  echo "❌ nix is required to run the repository formatter over '${changelog}'" >&2
  exit 1
}

before="$(sha256sum "${changelog}" | cut -d' ' -f1)"
before_bytes="$(wc -c <"${changelog}")"

nix fmt "${changelog}"

after="$(sha256sum "${changelog}" | cut -d' ' -f1)"
after_bytes="$(wc -c <"${changelog}")"

# Assert on the VALUE the hook set itself asserts on, capturing the checker's own
# rc rather than a pipeline's: a second pass in --fail-on-change mode must find
# nothing left to change. Reaching this fixed point is what proves no follow-up
# formatting commit is owed after the release.
rc=0
nix fmt -- --fail-on-change "${changelog}" || rc=$?
[[ ${rc} -ne 0 ]] && echo "❌ '${changelog}' is still not formatter-clean after formatting (treefmt --fail-on-change rc=${rc})" >&2 && exit 1

echo "✅ ${changelog} is formatter-clean: ${before} (${before_bytes} bytes) -> ${after} (${after_bytes} bytes), treefmt --fail-on-change rc=0"
