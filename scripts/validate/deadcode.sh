#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
case "$mode" in
production)
  # The example is the installed-API consumer; TestHelper and tests are absent.
  dart analyze lib/diene_config.dart lib/src example
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "$temp_dir"' EXIT
  dart compile exe example/diene_config_example.dart -o "$temp_dir/example" >/dev/null
  ;;
all)
  # Whole-repository pass includes the TestHelper and every test tier.
  dart analyze lib test example
  ;;
*)
  echo "usage: $0 production|all" >&2
  exit 2
  ;;
esac

echo "✅ Dart dead-code ${mode} pass completed without analyzer findings"
