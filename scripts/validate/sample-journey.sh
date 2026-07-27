#!/usr/bin/env bash
set -euo pipefail

source_help="$(pls run -- --help 2>&1)"
preview_help="$(pls preview -- --help 2>&1)"
if [[ ! -x dist/manager ]]; then
  echo "❌ preview did not build executable dist/manager" >&2
  exit 1
fi

required_flags=(
  enable-cluster
  enable-platform
  enable-dependency
  enable-traffic
  enable-webhook
  enable-cf-deploy
  enable-problem
  observe
  health-probe-bind-address
)
for flag_name in "${required_flags[@]}"; do
  if ! rg -q -- "-${flag_name}" <<<"${source_help}"; then
    echo "❌ source manager help omitted --${flag_name}" >&2
    exit 1
  fi
  if ! rg -q -- "-${flag_name}" <<<"${preview_help}"; then
    echo "❌ compiled manager help omitted --${flag_name}" >&2
    exit 1
  fi
  echo "PASS: --${flag_name} appears in source and compiled help"
done

retired_flags=("enable-"$'\x6e'"ote" "enable-"$'\x6a'"ournal")
for retired_flag in "${retired_flags[@]}"; do
  if rg -q -- "-${retired_flag}" <<<"${source_help}"; then
    echo "❌ source manager help retains a retired controller flag" >&2
    exit 1
  fi
  if rg -q -- "-${retired_flag}" <<<"${preview_help}"; then
    echo "❌ compiled manager help retains a retired controller flag" >&2
    exit 1
  fi
done

witness="$(go test -list '^TestManagerWiringRealControllerFlagsAndGlobalObserve$' ./tests/int/operator/)"
if ! rg -qx 'TestManagerWiringRealControllerFlagsAndGlobalObserve' <<<"${witness}"; then
  echo "❌ real-controller wiring witness was not discovered by exact name" >&2
  exit 1
fi
go test -count=1 -run '^TestManagerWiringRealControllerFlagsAndGlobalObserve$' ./tests/int/operator/

echo "✅ Operator real-surface journey passed"
