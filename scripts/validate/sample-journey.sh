#!/usr/bin/env bash
set -euo pipefail

source_help="$(pls run -- --help 2>&1)"
! rg -q 'enable-note' <<<"${source_help}" && echo "❌ source manager did not report the Note enable flag" >&2 && exit 1
! rg -q 'enable-journal' <<<"${source_help}" && echo "❌ source manager did not report the Journal enable flag" >&2 && exit 1

preview_help="$(pls preview -- --help 2>&1)"
[ ! -x dist/manager ] && echo "❌ preview did not build dist/manager" >&2 && exit 1
! rg -q 'health-probe-bind-address' <<<"${preview_help}" && echo "❌ compiled manager did not report its health endpoint flag" >&2 && exit 1
! rg -q 'observe' <<<"${preview_help}" && echo "❌ compiled manager did not report the observe flag" >&2 && exit 1

go test -count=1 -run '^TestMultiControllerWiring$' ./tests/int/operator/

echo "✅ Operator sample journey passed"
