#!/usr/bin/env bash
set -euo pipefail

# Push the built Linux packages (deb/rpm) to Gemfury. Instance values arrive via env (cd.yaml).
[ -z "${FURY_TOKEN:-}" ] && echo "❌ 'FURY_TOKEN' env var not set" >&2 && exit 1
[ -z "${FURY_ENDPOINT:-}" ] && echo "❌ 'FURY_ENDPOINT' env var not set" >&2 && exit 1

endpoint="${FURY_ENDPOINT}"

shopt -s nullglob
packages=(dist/*.deb dist/*.rpm)
[ "${#packages[@]}" -eq 0 ] && echo "❌ no deb/rpm packages found in dist/" >&2 && exit 1

for pkg in "${packages[@]}"; do
  echo "📤 pushing ${pkg} -> ${endpoint}"
  curl -fsS --connect-timeout 30 --max-time 600 -F package=@"${pkg}" "https://${FURY_TOKEN}@${endpoint}/"
done

echo "✅ pushed ${#packages[@]} package(s) to Gemfury"
