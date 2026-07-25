#!/usr/bin/env bash
set -euo pipefail

# The shared markdownlint pre-commit hook gates a fixed regex of documentation
# files and does not include this module's usage skill. This gate lints the
# usage skill markdown independently so it is not shipped unchecked, reusing the
# EXACT nix-generated markdownlint-cli2 the pre-commit hook uses. The absolute
# /nix/store executable is read out of the generated .pre-commit-config.yaml, so
# this gate needs no network and fails closed when the store executable is
# unavailable. It reads the repository .markdownlint-cli2.jsonc config.
skill="skills/diene-go-config-usage/SKILL.md"
[ -f "${skill}" ] || {
  echo "❌ config usage skill missing: ${skill}" >&2
  exit 1
}

entry="$(yq -r '.repos[].hooks[] | select(.id == "a-markdownlint") | .entry' .pre-commit-config.yaml 2>/dev/null || true)"
case "${entry}" in
/nix/store/*) ;;
*)
  echo "❌ could not resolve the nix-generated markdownlint-cli2 from .pre-commit-config.yaml" >&2
  exit 1
  ;;
esac
[ -x "${entry}" ] || {
  echo "❌ nix-generated markdownlint-cli2 is not executable: ${entry}" >&2
  exit 1
}

"${entry}" "${skill}"

echo "✅ Config usage skill markdown is lint-clean"
