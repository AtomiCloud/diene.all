#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
[ -z "${mode}" ] && echo "❌ dead-code mode not set" >&2 && exit 1

case "${mode}" in
whole)
  dart analyze .
  ;;
production)
  dart analyze lib
  ;;
*)
  echo "❌ unknown dead-code mode '${mode}'" >&2
  exit 1
  ;;
esac

echo "✅ Dart dead-code ${mode} pass complete"
